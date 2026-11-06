[Version = "1.0.0"]
section SCUDashboard;

// ============================================================================
// Constants (ported from the existing ad-hoc Hourly/Sessions queries)
// ============================================================================
TenantId = "e6cf700c-2029-4e98-aedd-f589e62f7316";
ClientId = "72bb0a2b-c028-4a0f-bb57-78a81db6fc18";
ApiAudience = "73c2949e-da2d-457a-9607-fcc665198967";
PodId = "ee221a39-3ce7-48ee-8b63-18bd56c52288";
Workspace = "default";
Capacity = "SecCo";
TokenEndpoint = "https://login.microsoftonline.com/" & TenantId & "/oauth2/v2.0/token";
BaseUrl = "https://us.api.securityplatform.microsoft.com/pods/" & PodId & "/workspaces/" & Workspace & "/securitycopilot/usage/" & Capacity;

// ============================================================================
// Auth: exchange the user-supplied refresh token ("Key") for an access token.
// ManualCredentials = true tells Power Query "I'm handling auth myself" so it
// does not attempt its own pre-flight credential validation on this call.
// ============================================================================
GetAccessToken = () as text =>
    let
        credential = Extension.CurrentCredential(),
        refreshToken = credential[Key],
        FormBody = "grant_type=refresh_token&client_id=" & ClientId & "&refresh_token=" & refreshToken
                   & "&scope=" & ApiAudience & "%2FPurview.DelegatedAccess%20offline_access",
        RawResponse = Web.Contents(TokenEndpoint, [
            Headers = [#"Content-Type" = "application/x-www-form-urlencoded"],
            Content = Text.ToBinary(FormBody),
            ManualCredentials = true,
            ManualStatusHandling = {400, 401}
        ]),
        Response = Json.Document(RawResponse),
        AccessToken =
            if Record.HasFields(Response, "access_token") then
                Response[access_token]
            else
                error Error.Record(
                    "DataSource.Error",
                    "Token exchange failed: " & (if Record.HasFields(Response, "error_description") then Response[error_description] else "Unknown error")
                )
    in
        AccessToken;

// ============================================================================
// TestConnection: lightweight check used by Power BI's credential dialog and
// by scheduled-refresh validation. Only does the token exchange (no data
// fetch), so it is fast, and it fully replaces Power BI's generic pre-flight
// check (which otherwise fails with 404 against this API).
// ============================================================================
shared SCUDashboard.TestConnection = () as text =>
    let
        token = GetAccessToken()
    in
        "OK: token acquired (" & Text.Start(token, 10) & "...)";

// ============================================================================
// Hourly data
// ============================================================================
GetHourlyData = () as table =>
    let
        Token = GetAccessToken(),
        NowUtc = DateTimeZone.RemoveZone(DateTimeZone.FixedUtcNow()),
        WindowStart = DateTime.ToText(NowUtc - #duration(30, 0, 0, 0), "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
        WindowEnd = DateTime.ToText(NowUtc, "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
        RequestBody = "{""startDate"":""" & WindowStart & """,""endDate"":""" & WindowEnd & """}",
        Response = Json.Document(Web.Contents(BaseUrl & "/aggregates/hourly", [
            Headers = [Authorization = "Bearer " & Token, #"Content-Type" = "application/json"],
            Content = Text.ToBinary(RequestBody),
            ManualCredentials = true
        ])),
        Rows = Response[value],
        RawTable = Table.FromRecords(Rows),
        Typed = Table.TransformColumnTypes(RawTable, {{"aggregateStartTime", type datetime}, {"usedCapacity", type number}, {"provisionedSCUUsed", type number}, {"overageSCUUsed", type number}, {"overageState", type text}}),
        Renamed = Table.RenameColumns(Typed, {{"aggregateStartTime", "Hour"}, {"usedCapacity", "SCU_Used"}, {"provisionedSCUUsed", "ProvisionedSCU"}, {"overageSCUUsed", "OverageSCU"}, {"overageState", "OverageState"}}),
        AddDay = Table.AddColumn(Renamed, "Day", each Date.From([Hour]), type date),
        AddHourOfDay = Table.AddColumn(AddDay, "HourOfDay", each Time.Hour(DateTime.Time([Hour])), Int64.Type),
        AddDayOfWeek = Table.AddColumn(AddHourOfDay, "DayOfWeek", each Date.ToText([Day], "dddd"), type text),
        Final = Table.SelectColumns(AddDayOfWeek, {"Hour", "Day", "HourOfDay", "DayOfWeek", "SCU_Used", "ProvisionedSCU", "OverageSCU", "OverageState"})
    in
        Final;

// ============================================================================
// Sessions data (paginated)
// ============================================================================
GetSessionsData = () as table =>
    let
        Token = GetAccessToken(),
        NowUtc = DateTimeZone.RemoveZone(DateTimeZone.FixedUtcNow()),
        WindowStart = DateTime.ToText(NowUtc - #duration(30, 0, 0, 0), "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
        WindowEnd = DateTime.ToText(NowUtc, "yyyy-MM-ddTHH:mm:ss.fff") & "Z",
        GetPage = (pageNumber as number) =>
            let
                RequestBody = "{""startDate"":""" & WindowStart & """,""endDate"":""" & WindowEnd & ""","
                    & """users"":[],""experiences"":[],""invocationTypes"":[],""plugins"":[],"
                    & """categories"":[],""invocationCategories"":[],"
                    & """pageSize"":200,""pageNumber"":" & Number.ToText(pageNumber) & ","
                    & """sortingDirection"":""descending""}",
                Response = Json.Document(Web.Contents(BaseUrl & "/aggregates/dimensional", [
                    Headers = [Authorization = "Bearer " & Token, #"Content-Type" = "application/json"],
                    Content = Text.ToBinary(RequestBody),
                    ManualCredentials = true
                ])),
                Rows = Response[value]
            in
                Rows,
        Pages = List.Generate(
            () => [Page = 1, Result = GetPage(1)],
            each List.Count([Result]) > 0,
            each [Page = [Page] + 1, Result = GetPage([Page] + 1)]
        ),
        AllRows = List.Combine(List.Transform(Pages, each _[Result])),
        RawTable = Table.FromRecords(AllRows),
        Typed = Table.TransformColumnTypes(RawTable, {{"aggregateStartTime", type datetime}, {"sessionId", type text}, {"usedCapacity", type number}, {"userName", type text}, {"invocationCategory", type text}, {"userDepartment", type text}, {"invocationType", type text}, {"copilotExperience", type text}, {"usageType", type text}, {"workload", type text}, {"evaluationId", type text}, {"unauthenticatedSourceApplicationId", type text}}),
        AddUserFriendly = Table.AddColumn(Typed, "UserFriendly", each if Text.StartsWith([userName], "SecurityCopilotAgentUser-") then "Agent-" & Text.Start(Text.AfterDelimiter([userName], "SecurityCopilotAgentUser-"), 8) else [userName], type text),
        AddIsAgent = Table.AddColumn(AddUserFriendly, "IsAgent", each [invocationCategory] = "Agent", type logical),
        AddPlugins = Table.AddColumn(AddIsAgent, "Plugins", each try Text.Combine(List.Transform([skillSetNames], each Text.From(_)), ", ") otherwise "", type text),
        AddPluginCount = Table.AddColumn(AddPlugins, "PluginCount", each try List.Count([skillSetNames]) otherwise 0, Int64.Type),
        AddSkills = Table.AddColumn(AddPluginCount, "Skills", each try Text.Combine(List.Transform([skillNames], each Text.From(_)), ", ") otherwise "", type text),
        AddSkillCount = Table.AddColumn(AddSkills, "SkillCount", each try List.Count([skillNames]) otherwise 0, Int64.Type),
        AddStatus = Table.AddColumn(AddSkillCount, "Status", each if [status] = null then "" else Text.From([status]), type text),
        Renamed = Table.RenameColumns(AddStatus, {{"aggregateStartTime", "Date"}, {"sessionId", "SessionId"}, {"usedCapacity", "SCU_Used"}, {"userName", "User"}, {"invocationCategory", "Category"}, {"userDepartment", "Department"}, {"invocationType", "Type"}, {"copilotExperience", "Experience"}, {"usageType", "UsageType"}, {"workload", "Workload"}, {"evaluationId", "EvaluationId"}, {"unauthenticatedSourceApplicationId", "SourceApp"}}),
        Final = Table.SelectColumns(Renamed, {"Date", "SessionId", "SCU_Used", "User", "UserFriendly", "IsAgent", "Department", "Category", "Type", "Experience", "Plugins", "PluginCount", "Skills", "SkillCount", "UsageType", "Workload", "EvaluationId", "Status", "SourceApp"})
    in
        Final;

// ============================================================================
// Navigation table exposing Hourly / Sessions in "Get Data"
// ============================================================================
shared SCUDashboard.Contents = Value.ReplaceType(SCUDashboardNavTable, type function () as table);

SCUDashboardNavTable = () as table =>
    let
        objects = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            {
                {"Hourly", "Hourly", GetHourlyData(), "Table", "Table", true},
                {"Sessions", "Sessions", GetSessionsData(), "Table", "Table", true}
            }
        ),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

// ============================================================================
// Data Source Kind description
// ============================================================================
SCUDashboard = [
    Authentication = [
        Key = [
            KeyLabel = "Refresh Token",
            Label = "Security Copilot Usage API - paste the OAuth refresh token"
        ]
    ],
    Label = "Security Copilot Usage Dashboard",
    TestConnection = (dataSourcePath) => {"SCUDashboard.TestConnection"}
];

// ============================================================================
// Publish info (Beta, shows under "Other" in Get Data)
// ============================================================================
SCUDashboard.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = {"Security Copilot Usage", "Connect to the Security Copilot Usage API"}
];

// ============================================================================
// Standard navigation-table helper (verbatim from Microsoft's Data Connector SDK samples)
// ============================================================================
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta
        [
            NavigationTable.NameColumn = nameColumn,
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn,
            Preview.DelayColumn = itemNameColumn,
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;
