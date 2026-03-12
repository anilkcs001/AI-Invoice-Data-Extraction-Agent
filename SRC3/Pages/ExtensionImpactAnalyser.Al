/// <summary>
/// Page hosting the Extension Impact Analyzer control add-in.
/// Allows a developer to select an extension, enter a new version,
/// and see which dependent extensions will break, need recompilation, or remain safe.
/// </summary>
page 50200 "Extension Impact Analyzer"
{
    PageType = Card;
    Caption = 'Extension Impact Analyzer';
    UsageCategory = Administration;
    ApplicationArea = All;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    LinksAllowed = false;
    ShowFilter = false;

    layout
    {
        area(Content)
        {
            usercontrol(ImpactControl; ImpactAnalyzer)
            {
                ApplicationArea = All;

                /// <summary>
                /// JS fires OnReady when DOM is built.
                /// We respond by loading the extension list.
                /// </summary>
                trigger OnReady()
                begin
                    IsControlReady := true;
                    LoadExtensionData();
                end;

                /// <summary>
                /// Fired when user selects an extension from the dropdown.
                /// We store the selection for potential use by actions.
                /// </summary>
                trigger OnExtensionSelected(AppId: Text; AppName: Text; CurrentVersion: Text)
                begin
                    SelectedAppId := AppId;
                    SelectedAppName := AppName;
                end;

                /// <summary>
                /// Fired when user clicks Analyze Impact.
                /// We run the analysis and send results back to JS.
                /// </summary>
                trigger OnAnalyzeRequested(AppId: Text; NewVersionMajor: Integer;
                                           NewVersionMinor: Integer; NewVersionBuild: Integer;
                                           NewVersionRevision: Integer)
                begin
                    RunImpactAnalysis(AppId, NewVersionMajor, NewVersionMinor,
                                     NewVersionBuild, NewVersionRevision);
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Refresh)
            {
                ApplicationArea = All;
                Caption = 'Refresh';
                ToolTip = 'Reload the extension list and clear results.';
                Image = Refresh;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                begin
                    if not IsControlReady then begin
                        Message('The control is still loading. Please wait.');
                        exit;
                    end;
                    Clear(LastImpactPayload);
                    LoadExtensionData();
                end;
            }

            action(ExportReport)
            {
                ApplicationArea = All;
                Caption = 'Export Report';
                ToolTip = 'Download the last impact analysis result as a JSON file.';
                Image = Export;
                Promoted = true;
                PromotedCategory = Process;
                PromotedOnly = true;

                trigger OnAction()
                var
                    TempBlob: Codeunit "Temp Blob";
                    OutStr: OutStream;
                    InStr: InStream;
                    FileName: Text;
                begin
                    if LastImpactPayload = '' then begin
                        Message('No analysis result to export. Run an analysis first.');
                        exit;
                    end;

                    TempBlob.CreateOutStream(OutStr, TextEncoding::UTF8);
                    OutStr.WriteText(LastImpactPayload);
                    TempBlob.CreateInStream(InStr, TextEncoding::UTF8);

                    FileName := 'ImpactReport_' +
                        SanitizeFileName(SelectedAppName) + '_' +
                        Format(Today, 0, '<Year4><Month,2><Day,2>') + '.json';

                    DownloadFromStream(InStr, 'Export Impact Report', '', 'JSON Files (*.json)|*.json', FileName);
                end;
            }
        }
    }

    var
        IsControlReady: Boolean;
        LastImpactPayload: Text;
        SelectedAppId: Text;
        SelectedAppName: Text;

    /// <summary>
    /// Loads the extension list from the codeunit and sends it to JS.
    /// </summary>
    local procedure LoadExtensionData()
    var
        Mgmt: Codeunit "Impact Analyzer Mgmt";
        JsonPayload: Text;
    begin
        if not TryGetExtensions(Mgmt, JsonPayload) then begin
            Message('Error loading extensions:\%1', GetLastErrorText());
            exit;
        end;
        CurrPage.ImpactControl.LoadExtensions(JsonPayload);
    end;

    /// <summary>
    /// Runs the impact analysis and sends results to JS.
    /// Shows a spinner during computation.
    /// </summary>
    local procedure RunImpactAnalysis(AppId: Text; Maj: Integer; Min: Integer; Bld: Integer; Rev: Integer)
    var
        Mgmt: Codeunit "Impact Analyzer Mgmt";
        AppGuid: Guid;
        JsonPayload: Text;
    begin
        CurrPage.ImpactControl.SetAnalyzing(true);

        // Convert text AppId to Guid
        if not Evaluate(AppGuid, AppId) then begin
            CurrPage.ImpactControl.SetAnalyzing(false);
            Message('Invalid App ID: %1', AppId);
            exit;
        end;

        if not TryComputeImpact(Mgmt, AppGuid, Maj, Min, Bld, Rev, JsonPayload) then begin
            CurrPage.ImpactControl.SetAnalyzing(false);
            Message('Error during analysis:\%1', GetLastErrorText());
            exit;
        end;

        LastImpactPayload := JsonPayload;
        CurrPage.ImpactControl.ShowImpactResult(JsonPayload);
        CurrPage.ImpactControl.SetAnalyzing(false);
    end;

    [TryFunction]
    local procedure TryGetExtensions(var Mgmt: Codeunit "Impact Analyzer Mgmt"; var Payload: Text)
    begin
        Mgmt.GetExtensionsJson(Payload);
    end;

    [TryFunction]
    local procedure TryComputeImpact(
        var Mgmt: Codeunit "Impact Analyzer Mgmt";
        AppGuid: Guid;
        Maj: Integer; Min: Integer; Bld: Integer; Rev: Integer;
        var Payload: Text)
    begin
        Mgmt.ComputeImpact(AppGuid, Maj, Min, Bld, Rev, Payload);
    end;

    /// <summary>
    /// Removes characters that are invalid in file names.
    /// </summary>
    local procedure SanitizeFileName(FileName: Text): Text
    begin
        FileName := DelChr(FileName, '=', '/\:*?"<>|');
        FileName := FileName.Replace(' ', '_');
        if FileName = '' then
            FileName := 'Extension';
        exit(FileName);
    end;
}