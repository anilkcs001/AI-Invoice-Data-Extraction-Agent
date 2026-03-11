// Page 71003 - AIDE Agent Setup
page 71003 "AIDE Agent Setup"
{
    Caption = 'AI Invoice Extraction Setup';
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    SourceTable = "AIDE Agent Setup";
    DeleteAllowed = false;
    InsertAllowed = false;

    layout
    {
        area(Content)
        {
            group(AzureDI)
            {
                Caption = '🔍 Azure Document Intelligence';

                field("Azure DI Endpoint"; Rec."Azure DI Endpoint")
                {
                    ApplicationArea = All;
                    ToolTip = 'Azure DI endpoint URL.';
                }
                field(AzureDIKey; AzureDIKeyValue)
                {
                    ApplicationArea = All;
                    Caption = 'Azure DI API Key';
                    ToolTip = 'API Key for Azure DI.';
                    ExtendedDatatype = Masked;

                    trigger OnValidate()
                    begin
                        Rec.SetSecret('AIDE_DI_KEY', AzureDIKeyValue);
                    end;
                }
                field("Azure DI Model ID"; Rec."Azure DI Model ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Model ID (prebuilt-invoice).';
                }
            }
            group(AzureOpenAI)
            {
                Caption = '🤖 Azure OpenAI';

                field("OpenAI Endpoint"; Rec."OpenAI Endpoint")
                {
                    ApplicationArea = All;
                    ToolTip = 'Azure OpenAI endpoint.';
                }
                field("OpenAI Deployment"; Rec."OpenAI Deployment")
                {
                    ApplicationArea = All;
                    ToolTip = 'Deployment name.';
                }
                field(OpenAIKey; OpenAIKeyValue)
                {
                    ApplicationArea = All;
                    Caption = 'Azure OpenAI API Key';
                    ToolTip = 'API Key for Azure OpenAI.';
                    ExtendedDatatype = Masked;

                    trigger OnValidate()
                    begin
                        Rec.SetSecret('AIDE_OPENAI_KEY', OpenAIKeyValue);
                    end;
                }
            }
            group(Matching)
            {
                Caption = '🔗 Entity Matching';

                field("Auto Match Vendor"; Rec."Auto Match Vendor")
                {
                    ApplicationArea = All;
                    ToolTip = 'Auto-match vendors by GSTIN.';
                }
                field("Auto Match Customer"; Rec."Auto Match Customer")
                {
                    ApplicationArea = All;
                    ToolTip = 'Auto-match customers by GSTIN.';
                }
                field("Auto Match Items"; Rec."Auto Match Items")
                {
                    ApplicationArea = All;
                    ToolTip = 'Auto-match items by HSN/description.';
                }
            }
            group(Validation)
            {
                Caption = '✅ Validation';

                field("Confidence Threshold %"; Rec."Confidence Threshold %")
                {
                    ApplicationArea = All;
                    ToolTip = 'Minimum OCR confidence threshold.';
                }
                field("Enable GST Validation"; Rec."Enable GST Validation")
                {
                    ApplicationArea = All;
                    ToolTip = 'Validate GST calculations.';
                }
                field("Amt. Tolerance (LCY)"; Rec."Amt. Tolerance (LCY)")
                {
                    ApplicationArea = All;
                    ToolTip = 'Amount tolerance for validation.';
                }
            }
            group(NumberSeries)
            {
                Caption = '🔢 Number Series';

                field("Staging Doc. Nos."; Rec."Staging Doc. Nos.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Number series for staging documents.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestDIConnection)
            {
                Caption = 'Test DI Connection';
                ApplicationArea = All;
                Image = TestFile;
                ToolTip = 'Test Azure DI connection.';

                trigger OnAction()
                var
                    Client: HttpClient;
                    ReqMsg: HttpRequestMessage;
                    ResMsg: HttpResponseMessage;
                    Headers: HttpHeaders;
                begin
                    Rec.TestField("Azure DI Endpoint");
                    ReqMsg.SetRequestUri(Rec."Azure DI Endpoint" +
                        '/formrecognizer/documentModels?api-version=2023-07-31');
                    ReqMsg.Method := 'GET';
                    ReqMsg.GetHeaders(Headers);
                    Headers.Add('Ocp-Apim-Subscription-Key', Rec.GetSecret('AIDE_DI_KEY'));

                    if Client.Send(ReqMsg, ResMsg) then begin
                        if ResMsg.IsSuccessStatusCode() then
                            Message('✅ Azure DI connection successful!')
                        else
                            Error('❌ HTTP %1', ResMsg.HttpStatusCode());
                    end else
                        Error('❌ Connection failed');
                end;
            }
            action(TestOpenAIConnection)
            {
                Caption = 'Test OpenAI Connection';
                ApplicationArea = All;
                Image = TestReport;
                ToolTip = 'Test Azure OpenAI connection.';

                trigger OnAction()
                var
                    Client: HttpClient;
                    ReqMsg: HttpRequestMessage;
                    ResMsg: HttpResponseMessage;
                    ReqContent: HttpContent;
                    ContentHeaders: HttpHeaders;
                    Headers: HttpHeaders;
                    Body: JsonObject;
                    Msgs: JsonArray;
                    Msg: JsonObject;
                    BodyText: Text;
                    ResponseText: Text;
                begin
                    Rec.TestField("OpenAI Endpoint");
                    Rec.TestField("OpenAI Deployment");

                    Msg.Add('role', 'user');
                    Msg.Add('content', 'Say hello');
                    Msgs.Add(Msg);
                    Body.Add('messages', Msgs);
                    Body.Add('max_tokens', 10);
                    Body.WriteTo(BodyText);

                    ReqContent.WriteFrom(BodyText);
                    ReqContent.GetHeaders(ContentHeaders);
                    if ContentHeaders.Contains('Content-Type') then
                        ContentHeaders.Remove('Content-Type');
                    ContentHeaders.Add('Content-Type', 'application/json');

                    ReqMsg.SetRequestUri(Rec."OpenAI Endpoint" +
                        '/openai/deployments/' + Rec."OpenAI Deployment" +
                        '/chat/completions?api-version=2024-02-15-preview');
                    ReqMsg.Method := 'POST';
                    ReqMsg.Content := ReqContent;
                    ReqMsg.GetHeaders(Headers);
                    Headers.Add('api-key', Rec.GetSecret('AIDE_OPENAI_KEY'));

                    if Client.Send(ReqMsg, ResMsg) then begin
                        if ResMsg.IsSuccessStatusCode() then
                            Message('✅ Azure OpenAI connection successful!')
                        else begin
                            ResMsg.Content.ReadAs(ResponseText);
                            Error('❌ HTTP %1: %2', ResMsg.HttpStatusCode(), ResponseText);
                        end;
                    end else
                        Error('❌ Connection failed');
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        Rec.Reset();
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;

    var
        AzureDIKeyValue: Text;
        OpenAIKeyValue: Text;
}