// Codeunit 71004 - AIDE Agent Orchestrator
codeunit 71004 "AIDE Agent Orchestrator"
{
    Caption = 'AI Invoice Agent Orchestrator';

    /// <summary>
    /// FULL WORKFLOW: Upload → Select Type → Extract → Validate → Match → Show → Confirm → Insert
    /// </summary>
    procedure RunFullAgentWorkflow()
    var
        Header: Record "AIDE Extracted Inv. Header";
        Direction: Enum "AIDE Document Direction";
        InStr: InStream;
        FileName: Text;
        ConfirmedByUser: Boolean;
    begin
        // ── STEP 1: Ask user for Document Type ──
        Direction := AskDocumentDirection();

        // ── STEP 2: Upload File ──
        if not UploadFile(InStr, FileName) then begin
            Message('Upload cancelled.');
            exit;
        end;

        // ── STEP 3: Create staging record ──
        Header := CreateStagingRecord(Direction, FileName, InStr);
        Commit();

        // ── STEP 4: Extract data via OCR + AI ──
        ExtractData(Header, InStr, FileName);
        Commit();

        // ── STEP 5: Validate extracted data ──
        ValidateData(Header);
        Commit();

        // ── STEP 6: Match BC entities ──
        MatchEntities(Header);
        Commit();

        // ── STEP 7: Show extracted data for review & confirmation ──
        Header."Extraction Status" := Header."Extraction Status"::"Awaiting Confirmation";
        Header.Modify(true);
        Commit();

        ConfirmedByUser := ShowForConfirmation(Header);

        if not ConfirmedByUser then begin
            Header."Extraction Status" := Header."Extraction Status"::Rejected;
            Header.Modify(true);
            Message('Document rejected by user. No posting performed.');
            exit;
        end;

        // ── STEP 8: User confirmed → Create & Insert into BC ──
        Header."Extraction Status" := Header."Extraction Status"::Confirmed;
        Header."Confirmed By" := CopyStr(UserId, 1, MaxStrLen(Header."Confirmed By"));
        Header."Confirmed DateTime" := CurrentDateTime;
        Header.Modify(true);
        Commit();

        InsertIntoBCAfterConfirmation(Header);
    end;

    /// <summary>
    /// Step 1: Ask user for Purchase or Sales
    /// </summary>
    local procedure AskDocumentDirection(): Enum "AIDE Document Direction"
    var
        Choices: Text;
        Selected: Integer;
    begin
        Choices := 'Purchase Invoice,Sales Invoice';
        Selected := StrMenu(Choices, 1, 'Select Document Type:');

        case Selected of
            0:
                Error('Operation cancelled.');
            1:
                exit("AIDE Document Direction"::Purchase);
            2:
                exit("AIDE Document Direction"::Sales);
        end;
    end;

    /// <summary>
    /// Step 2: Upload file
    /// </summary>
    local procedure UploadFile(var InStr: InStream; var FileName: Text): Boolean
    begin
        exit(UploadIntoStream(
            'Upload Invoice (PDF/Image)',
            '',
            'PDF Files (*.pdf)|*.pdf|Image Files (*.jpg;*.png;*.tiff)|*.jpg;*.png;*.tiff|All Files (*.*)|*.*',
            FileName,
            InStr));
    end;

    /// <summary>
    /// Step 3: Create staging record and save file
    /// </summary>
    local procedure CreateStagingRecord(Direction: Enum "AIDE Document Direction"; FileName: Text; InStr: InStream): Record "AIDE Extracted Inv. Header"
    var
        Header: Record "AIDE Extracted Inv. Header";
        OutStr: OutStream;
    begin
        Header.Init();
        Header."Document Direction" := Direction;
        Header."Source File Name" := CopyStr(FileName, 1, MaxStrLen(Header."Source File Name"));
        Header."Extraction Status" := Header."Extraction Status"::Pending;
        Header.Insert(true);

        // Save source file
        Header."Source File Content".CreateOutStream(OutStr);
        CopyStream(OutStr, InStr);
        Header.Modify();

        exit(Header);
    end;

    /// <summary>
    /// Step 4: Run OCR + AI extraction
    /// </summary>
    local procedure ExtractData(var Header: Record "AIDE Extracted Inv. Header"; InStr: InStream; FileName: Text)
    var
        Engine: Codeunit "AIDE Extraction Engine";
    begin
        // Re-read the stream from saved blob since original InStr may be consumed
        Header.CalcFields("Source File Content");
        Header."Source File Content".CreateInStream(InStr);

        Engine.ExtractFromFile(Header, InStr, FileName);
    end;

    /// <summary>
    /// Step 5: Validate
    /// </summary>
    local procedure ValidateData(var Header: Record "AIDE Extracted Inv. Header")
    var
        Validator: Codeunit "AIDE Validation Engine";
    begin
        Validator.ValidateExtractedData(Header);
    end;

    /// <summary>
    /// Step 6: Match entities
    /// </summary>
    local procedure MatchEntities(var Header: Record "AIDE Extracted Inv. Header")
    var
        Matcher: Codeunit "AIDE Entity Matcher";
    begin
        Matcher.MatchEntities(Header);
    end;

    /// <summary>
    /// Step 7: Show the extracted data card for user review
    /// Returns true if user confirms, false if rejected
    /// </summary>
    local procedure ShowForConfirmation(var Header: Record "AIDE Extracted Inv. Header"): Boolean
    var
        ConfirmPage: Page "AIDE Confirmation Card";
        UserAction: Action;
    begin
        ConfirmPage.SetRecord(Header);
        ConfirmPage.SetConfirmationMode(true);
        UserAction := ConfirmPage.RunModal();

        // Re-read in case user modified data
        Header.Get(Header."Entry No.");

        exit(UserAction = Action::LookupOK); // OK = Confirm
    end;

    /// <summary>
    /// Step 8: After confirmation, create the BC document
    /// </summary>
    local procedure InsertIntoBCAfterConfirmation(var Header: Record "AIDE Extracted Inv. Header")
    var
        DocCreator: Codeunit "AIDE Document Creator";
        CreatedNo: Code[20];
        ShouldPost: Boolean;
    begin
        CreatedNo := DocCreator.CreateDocument(Header);

        ShouldPost := Confirm(
            'Document %1 created successfully as %2 %3.\Do you want to POST it now?',
            false,
            Header."Entry No.",
            Header."Created Doc. Type",
            CreatedNo);

        if ShouldPost then begin
            DocCreator.PostDocument(Header);
            Message(
                '✅ SUCCESS!\Document %1 has been posted.\Posted No.: %2\Type: %3',
                Header."Entry No.",
                Header."Posted Doc. No.",
                Header."Created Doc. Type");
        end else begin
            Message(
                '📄 Document created but NOT posted.\%1: %2\You can post it manually from the document list.',
                Header."Created Doc. Type",
                CreatedNo);
        end;
    end;

    /// <summary>
    /// Quick process: for calling from document list or API
    /// </summary>
    procedure ProcessExistingDocument(var Header: Record "AIDE Extracted Inv. Header")
    var
        InStr: InStream;
    begin
        Header.CalcFields("Source File Content");
        if not Header."Source File Content".HasValue then
            Error('No source file attached to document %1', Header."Entry No.");

        Header."Source File Content".CreateInStream(InStr);
        ExtractData(Header, InStr, Header."Source File Name");
        Commit();

        ValidateData(Header);
        MatchEntities(Header);

        Header."Extraction Status" := Header."Extraction Status"::"Awaiting Confirmation";
        Header.Modify(true);
    end;
}