// Codeunit 71000 - AI Extraction Engine (Core OCR + GPT Parser)
codeunit 71000 "AIDE Extraction Engine"
{
    Caption = 'AI Data Extraction Engine';
    Access = Internal;

    var
        Setup: Record "AIDE Agent Setup";
        SetupRead: Boolean;

    /// <summary>
    /// Main entry: takes file stream, sends to Azure DI, parses with GPT prompt, populates staging tables
    /// </summary>
    procedure ExtractFromFile(
        var Header: Record "AIDE Extracted Inv. Header";
        InStr: InStream;
        FileName: Text)
    var
        Base64Convert: Codeunit "Base64 Convert";
        Base64Content: Text;
        OCRRawText: Text;
        StructuredJSON: Text;
        StartTime: DateTime;
    begin
        ReadSetup();
        StartTime := CurrentDateTime;

        Header."Extraction Status" := Header."Extraction Status"::Pending;
        Header.Modify(true);
        Commit();

        // Step 1: Convert file to Base64
        Base64Content := Base64Convert.ToBase64(InStr);

        // Step 2: Send to Azure Document Intelligence
        OCRRawText := CallAzureDocumentIntelligence(Base64Content);

        // Step 3: Send OCR text to GPT with structured extraction prompt
        StructuredJSON := CallGPTForStructuredExtraction(OCRRawText, Header."Document Direction");

        // Step 4: Parse JSON and populate tables
        ParseAndPopulate(Header, StructuredJSON);

        // Step 5: Store raw JSON
        Header.SetRawJSON(StructuredJSON);

        Header."Extraction Status" := Header."Extraction Status"::Extracted;
        Header.Modify(true);
    end;

    local procedure CallAzureDocumentIntelligence(Base64Content: Text): Text
    var
        Client: HttpClient;
        ReqMsg: HttpRequestMessage;
        ResMsg: HttpResponseMessage;
        ReqContent: HttpContent;
        ReqHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
        ResponseText: Text;
        RequestBody: Text;
        JBody: JsonObject;
        OperationLocation: Text;
        AnalysisResult: Text;
        Attempt: Integer;
        MaxAttempts: Integer;
        IsComplete: Boolean;
    begin
        ReadSetup();
        Setup.TestField("Azure DI Endpoint");

        // Build request
        JBody.Add('base64Source', Base64Content);
        JBody.WriteTo(RequestBody);

        ReqContent.WriteFrom(RequestBody);
        ReqContent.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        ReqMsg.SetRequestUri(
            Setup."Azure DI Endpoint" +
            '/formrecognizer/documentModels/' +
            Setup."Azure DI Model ID" +
            ':analyze?api-version=2023-07-31');
        ReqMsg.Method := 'POST';
        ReqMsg.Content := ReqContent;
        ReqMsg.GetHeaders(ReqHeaders);
        ReqHeaders.Add('Ocp-Apim-Subscription-Key', Setup.GetSecret('AIDE_DI_KEY'));

        if not Client.Send(ReqMsg, ResMsg) then
            Error('Azure DI connection failed: %1', GetLastErrorText());

        if not ResMsg.IsSuccessStatusCode() then begin
            ResMsg.Content.ReadAs(ResponseText);
            Error('Azure DI error HTTP %1: %2', ResMsg.HttpStatusCode(), ResponseText);
        end;

        // Get operation location
        if not ResMsg.Headers.Get('Operation-Location', OperationLocation) then
            Error('No Operation-Location header returned');

        // Poll for completion
        MaxAttempts := 60;
        Attempt := 0;
        IsComplete := false;

        while (not IsComplete) and (Attempt < MaxAttempts) do begin
            Sleep(2000);
            Attempt += 1;

            Clear(Client);
            Clear(ReqMsg);
            Clear(ResMsg);

            ReqMsg.SetRequestUri(OperationLocation);
            ReqMsg.Method := 'GET';
            ReqMsg.GetHeaders(ReqHeaders);
            ReqHeaders.Add('Ocp-Apim-Subscription-Key', Setup.GetSecret('AIDE_DI_KEY'));

            if Client.Send(ReqMsg, ResMsg) then
                if ResMsg.IsSuccessStatusCode() then begin
                    ResMsg.Content.ReadAs(AnalysisResult);
                    IsComplete := CheckAnalysisStatus(AnalysisResult);
                end;
        end;

        if not IsComplete then
            Error('Azure DI analysis timed out after %1 seconds', MaxAttempts * 2);

        // Extract content text from result
        exit(ExtractContentFromDIResult(AnalysisResult));
    end;

    local procedure CheckAnalysisStatus(ResponseText: Text): Boolean
    var
        JObj: JsonObject;
        JTok: JsonToken;
        Status: Text;
    begin
        JObj.ReadFrom(ResponseText);
        if JObj.Get('status', JTok) then begin
            Status := JTok.AsValue().AsText();
            if Status = 'failed' then
                Error('Azure DI analysis failed');
            exit(Status = 'succeeded');
        end;
    end;

    local procedure ExtractContentFromDIResult(FullResult: Text): Text
    var
        JObj: JsonObject;
        JTok: JsonToken;
        JResult: JsonObject;
        ContentText: Text;
    begin
        JObj.ReadFrom(FullResult);
        if JObj.Get('analyzeResult', JTok) then begin
            JResult := JTok.AsObject();
            if JResult.Get('content', JTok) then
                ContentText := JTok.AsValue().AsText();
        end;
        exit(ContentText);
    end;

    local procedure CallGPTForStructuredExtraction(OCRText: Text; Direction: Enum "AIDE Document Direction"): Text
    var
        Client: HttpClient;
        ReqMsg: HttpRequestMessage;
        ResMsg: HttpResponseMessage;
        ReqContent: HttpContent;
        ContentHeaders: HttpHeaders;
        ReqHeaders: HttpHeaders;
        RequestBody: JsonObject;
        MessagesArray: JsonArray;
        SystemMsg: JsonObject;
        UserMsg: JsonObject;
        ResponseText: Text;
        JResponse: JsonObject;
        JChoices: JsonArray;
        JChoice: JsonObject;
        JMessage: JsonObject;
        JTok: JsonToken;
        ExtractedJSON: Text;
    begin
        ReadSetup();
        Setup.TestField("OpenAI Endpoint");
        Setup.TestField("OpenAI Deployment");

        // Build system prompt
        SystemMsg.Add('role', 'system');
        SystemMsg.Add('content', GetSystemPrompt(Direction));
        MessagesArray.Add(SystemMsg);

        // Build user message with OCR text
        UserMsg.Add('role', 'user');
        UserMsg.Add('content', 'Extract invoice data from this OCR text:\n\n' + OCRText);
        MessagesArray.Add(UserMsg);

        RequestBody.Add('messages', MessagesArray);
        RequestBody.Add('temperature', 0.0);
        RequestBody.Add('max_tokens', 4000);
        RequestBody.Add('response_format', BuildJSONResponseFormat());

        ReqContent.WriteFrom(FormatJsonObject(RequestBody));
        ReqContent.GetHeaders(ContentHeaders);
        if ContentHeaders.Contains('Content-Type') then
            ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        ReqMsg.SetRequestUri(
            Setup."OpenAI Endpoint" +
            '/openai/deployments/' +
            Setup."OpenAI Deployment" +
            '/chat/completions?api-version=2024-02-15-preview');
        ReqMsg.Method := 'POST';
        ReqMsg.Content := ReqContent;
        ReqMsg.GetHeaders(ReqHeaders);
        ReqHeaders.Add('api-key', Setup.GetSecret('AIDE_OPENAI_KEY'));

        if not Client.Send(ReqMsg, ResMsg) then
            Error('Azure OpenAI connection failed: %1', GetLastErrorText());

        if not ResMsg.IsSuccessStatusCode() then begin
            ResMsg.Content.ReadAs(ResponseText);
            Error('Azure OpenAI error HTTP %1: %2', ResMsg.HttpStatusCode(), ResponseText);
        end;

        ResMsg.Content.ReadAs(ResponseText);

        // Parse GPT response
        JResponse.ReadFrom(ResponseText);
        JResponse.Get('choices', JTok);
        JChoices := JTok.AsArray();
        JChoices.Get(0, JTok);
        JChoice := JTok.AsObject();
        JChoice.Get('message', JTok);
        JMessage := JTok.AsObject();
        JMessage.Get('content', JTok);
        ExtractedJSON := JTok.AsValue().AsText();

        exit(ExtractedJSON);
    end;

    local procedure GetSystemPrompt(Direction: Enum "AIDE Document Direction"): Text
    var
        Prompt: TextBuilder;
    begin
        Prompt.AppendLine('You are an Invoice Data Extraction Agent for Microsoft Business Central.');
        Prompt.AppendLine('');
        Prompt.AppendLine('A vendor invoice OCR text will be provided to you. Extract all data and return ONLY a valid JSON object.');
        Prompt.AppendLine('No explanation, no markdown, no extra text. First character must be { and last must be }.');
        Prompt.AppendLine('');
        Prompt.AppendLine('Return this exact JSON structure:');
        Prompt.AppendLine(GetJSONTemplate());
        Prompt.AppendLine('');
        Prompt.AppendLine('RULES:');
        Prompt.AppendLine('1. If a field is not found in the invoice, return null for strings and 0.00 for numbers.');
        Prompt.AppendLine('2. Never invent or guess values. Only extract what is clearly visible.');
        Prompt.AppendLine('3. Dates must always be in YYYY-MM-DD format.');
        Prompt.AppendLine('4. If CGST + SGST are present, set igst_rate and igst_amount to 0. If IGST is present, set cgst and sgst to 0.');
        Prompt.AppendLine('5. Verify: subtotal + total_tax + round_off must equal grand_total. If not, set needs_review to true and explain in review_reason.');
        Prompt.AppendLine('6. If grand_total on invoice does not match your calculated total, set needs_review to true.');
        Prompt.AppendLine('7. Return ONLY the JSON. Nothing else.');

        if Direction = Direction::Sales then
            Prompt.AppendLine('8. This is a SALES invoice - the buyer is our customer, the vendor/supplier is us.');

        exit(Prompt.ToText());
    end;

    local procedure GetJSONTemplate(): Text
    var
        T: TextBuilder;
    begin
        T.AppendLine('{');
        T.AppendLine('  "invoice_number": "",');
        T.AppendLine('  "invoice_date": "YYYY-MM-DD",');
        T.AppendLine('  "due_date": "YYYY-MM-DD",');
        T.AppendLine('  "po_reference": "",');
        T.AppendLine('  "currency": "INR",');
        T.AppendLine('  "vendor_name": "",');
        T.AppendLine('  "vendor_gstin": "",');
        T.AppendLine('  "vendor_address": "",');
        T.AppendLine('  "buyer_name": "",');
        T.AppendLine('  "buyer_gstin": "",');
        T.AppendLine('  "irn": "",');
        T.AppendLine('  "ack_number": "",');
        T.AppendLine('  "ack_date": "YYYY-MM-DD",');
        T.AppendLine('  "line_items": [');
        T.AppendLine('    {');
        T.AppendLine('      "line_no": 1,');
        T.AppendLine('      "description": "",');
        T.AppendLine('      "hsn_sac": "",');
        T.AppendLine('      "quantity": 0.00,');
        T.AppendLine('      "unit": "",');
        T.AppendLine('      "unit_price": 0.00,');
        T.AppendLine('      "discount_amount": 0.00,');
        T.AppendLine('      "taxable_amount": 0.00,');
        T.AppendLine('      "cgst_rate": 0.00,');
        T.AppendLine('      "cgst_amount": 0.00,');
        T.AppendLine('      "sgst_rate": 0.00,');
        T.AppendLine('      "sgst_amount": 0.00,');
        T.AppendLine('      "igst_rate": 0.00,');
        T.AppendLine('      "igst_amount": 0.00,');
        T.AppendLine('      "cess_amount": 0.00,');
        T.AppendLine('      "line_total": 0.00');
        T.AppendLine('    }');
        T.AppendLine('  ],');
        T.AppendLine('  "subtotal": 0.00,');
        T.AppendLine('  "total_cgst": 0.00,');
        T.AppendLine('  "total_sgst": 0.00,');
        T.AppendLine('  "total_igst": 0.00,');
        T.AppendLine('  "total_cess": 0.00,');
        T.AppendLine('  "total_tax": 0.00,');
        T.AppendLine('  "round_off": 0.00,');
        T.AppendLine('  "grand_total": 0.00,');
        T.AppendLine('  "amount_in_words": "",');
        T.AppendLine('  "bank_name": "",');
        T.AppendLine('  "account_number": "",');
        T.AppendLine('  "ifsc_code": "",');
        T.AppendLine('  "needs_review": false,');
        T.AppendLine('  "review_reason": ""');
        T.AppendLine('}');
        exit(T.ToText());
    end;

    local procedure BuildJSONResponseFormat(): JsonObject
    var
        JFormat: JsonObject;
    begin
        JFormat.Add('type', 'json_object');
        exit(JFormat);
    end;

    local procedure FormatJsonObject(JObj: JsonObject): Text
    var
        Result: Text;
    begin
        JObj.WriteTo(Result);
        exit(Result);
    end;

    /// <summary>
    /// Parse the structured JSON from GPT and populate header + lines
    /// </summary>
    local procedure ParseAndPopulate(var Header: Record "AIDE Extracted Inv. Header"; JSONText: Text)
    var
        JObj: JsonObject;
        JTok: JsonToken;
        JArr: JsonArray;
        JItem: JsonObject;
        Line: Record "AIDE Extracted Inv. Line";
        LineNo: Integer;
        i: Integer;
    begin
        JObj.ReadFrom(JSONText);

        // HEADER FIELDS
        Header."Invoice Number" := CopyStr(GetJsonText(JObj, 'invoice_number'), 1, MaxStrLen(Header."Invoice Number"));
        Header."Invoice Date" := GetJsonDate(JObj, 'invoice_date');
        Header."Due Date" := GetJsonDate(JObj, 'due_date');
        Header."PO Reference" := CopyStr(GetJsonText(JObj, 'po_reference'), 1, MaxStrLen(Header."PO Reference"));
        Header."Currency Code" := CopyStr(GetJsonText(JObj, 'currency'), 1, MaxStrLen(Header."Currency Code"));

        Header."Vendor Name" := CopyStr(GetJsonText(JObj, 'vendor_name'), 1, MaxStrLen(Header."Vendor Name"));
        Header."Vendor GSTIN" := CopyStr(GetJsonText(JObj, 'vendor_gstin'), 1, MaxStrLen(Header."Vendor GSTIN"));
        Header."Vendor Address" := CopyStr(GetJsonText(JObj, 'vendor_address'), 1, MaxStrLen(Header."Vendor Address"));

        Header."Buyer Name" := CopyStr(GetJsonText(JObj, 'buyer_name'), 1, MaxStrLen(Header."Buyer Name"));
        Header."Buyer GSTIN" := CopyStr(GetJsonText(JObj, 'buyer_gstin'), 1, MaxStrLen(Header."Buyer GSTIN"));

        Header.IRN := CopyStr(GetJsonText(JObj, 'irn'), 1, MaxStrLen(Header.IRN));
        Header."Ack Number" := CopyStr(GetJsonText(JObj, 'ack_number'), 1, MaxStrLen(Header."Ack Number"));
        Header."Ack Date" := GetJsonDate(JObj, 'ack_date');

        Header.Subtotal := GetJsonDecimal(JObj, 'subtotal');
        Header."Total CGST" := GetJsonDecimal(JObj, 'total_cgst');
        Header."Total SGST" := GetJsonDecimal(JObj, 'total_sgst');
        Header."Total IGST" := GetJsonDecimal(JObj, 'total_igst');
        Header."Total Cess" := GetJsonDecimal(JObj, 'total_cess');
        Header."Total Tax" := GetJsonDecimal(JObj, 'total_tax');
        Header."Round Off" := GetJsonDecimal(JObj, 'round_off');
        Header."Grand Total" := GetJsonDecimal(JObj, 'grand_total');
        Header."Amount In Words" := CopyStr(GetJsonText(JObj, 'amount_in_words'), 1, MaxStrLen(Header."Amount In Words"));

        Header."Bank Name" := CopyStr(GetJsonText(JObj, 'bank_name'), 1, MaxStrLen(Header."Bank Name"));
        Header."Account Number" := CopyStr(GetJsonText(JObj, 'account_number'), 1, MaxStrLen(Header."Account Number"));
        Header."IFSC Code" := CopyStr(GetJsonText(JObj, 'ifsc_code'), 1, MaxStrLen(Header."IFSC Code"));

        Header."Needs Review" := GetJsonBoolean(JObj, 'needs_review');
        Header."Review Reason" := CopyStr(GetJsonText(JObj, 'review_reason'), 1, MaxStrLen(Header."Review Reason"));

        // Determine tax structure
        if Header."Total IGST" > 0 then
            Header."Tax Structure" := Header."Tax Structure"::IGST
        else if (Header."Total CGST" > 0) or (Header."Total SGST" > 0) then
            Header."Tax Structure" := Header."Tax Structure"::"CGST+SGST"
        else
            Header."Tax Structure" := Header."Tax Structure"::None;

        Header.Modify(true);

        // LINE ITEMS
        Line.SetRange("Document Entry No.", Header."Entry No.");
        Line.DeleteAll();

        if JObj.Get('line_items', JTok) then begin
            JArr := JTok.AsArray();
            for i := 0 to JArr.Count - 1 do begin
                JArr.Get(i, JTok);
                JItem := JTok.AsObject();
                LineNo := (i + 1) * 10000;

                Line.Init();
                Line."Document Entry No." := Header."Entry No.";
                Line."Line No." := LineNo;
                Line.Description := CopyStr(GetJsonText(JItem, 'description'), 1, MaxStrLen(Line.Description));
                Line."HSN/SAC Code" := CopyStr(GetJsonText(JItem, 'hsn_sac'), 1, MaxStrLen(Line."HSN/SAC Code"));
                Line.Quantity := GetJsonDecimal(JItem, 'quantity');
                Line."Unit of Measure" := CopyStr(GetJsonText(JItem, 'unit'), 1, MaxStrLen(Line."Unit of Measure"));
                Line."Unit Price" := GetJsonDecimal(JItem, 'unit_price');
                Line."Discount Amount" := GetJsonDecimal(JItem, 'discount_amount');
                Line."Taxable Amount" := GetJsonDecimal(JItem, 'taxable_amount');
                Line."CGST Rate %" := GetJsonDecimal(JItem, 'cgst_rate');
                Line."CGST Amount" := GetJsonDecimal(JItem, 'cgst_amount');
                Line."SGST Rate %" := GetJsonDecimal(JItem, 'sgst_rate');
                Line."SGST Amount" := GetJsonDecimal(JItem, 'sgst_amount');
                Line."IGST Rate %" := GetJsonDecimal(JItem, 'igst_rate');
                Line."IGST Amount" := GetJsonDecimal(JItem, 'igst_amount');
                Line."Cess Amount" := GetJsonDecimal(JItem, 'cess_amount');
                Line."Line Total" := GetJsonDecimal(JItem, 'line_total');
                Line.Insert(true);
            end;
        end;
    end;

    // JSON Helper functions
    local procedure GetJsonText(JObj: JsonObject; Key: Text): Text
    var
        JTok: JsonToken;
    begin
        if JObj.Get(Key, JTok) then
            if not JTok.AsValue().IsNull then
                exit(JTok.AsValue().AsText());
        exit('');
    end;

    local procedure GetJsonDecimal(JObj: JsonObject; Key: Text): Decimal
    var
        JTok: JsonToken;
        Result: Decimal;
    begin
        if JObj.Get(Key, JTok) then
            if not JTok.AsValue().IsNull then
                if Evaluate(Result, JTok.AsValue().AsText()) then
                    exit(Result);
        exit(0);
    end;

    local procedure GetJsonDate(JObj: JsonObject; Key: Text): Date
    var
        JTok: JsonToken;
        DateText: Text;
        Result: Date;
    begin
        if JObj.Get(Key, JTok) then
            if not JTok.AsValue().IsNull then begin
                DateText := JTok.AsValue().AsText();
                if Evaluate(Result, DateText) then
                    exit(Result);
            end;
        exit(0D);
    end;

    local procedure GetJsonBoolean(JObj: JsonObject; Key: Text): Boolean
    var
        JTok: JsonToken;
    begin
        if JObj.Get(Key, JTok) then
            if not JTok.AsValue().IsNull then
                exit(JTok.AsValue().AsBoolean());
        exit(false);
    end;

    local procedure ReadSetup()
    begin
        if SetupRead then
            exit;
        Setup.GetSetup();
        SetupRead := true;
    end;
}