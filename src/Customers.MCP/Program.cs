using AzureCosmosDB.MCP.Toolkit.Services;
using Azure.Identity;
using Microsoft.Azure.Cosmos;

var builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry
var appInsightsConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrEmpty(appInsightsConnectionString))
{
    builder.Services.AddApplicationInsightsTelemetry(options =>
    {
        options.ConnectionString = appInsightsConnectionString;
    });
}

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Configure Cosmos DB Client
var cosmosEndpoint = builder.Configuration["COSMOSDB_ENDPOINT"] 
    ?? throw new InvalidOperationException("COSMOSDB_ENDPOINT configuration is missing");

builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var credential = new DefaultAzureCredential();
    return new CosmosClient(cosmosEndpoint, credential);
});

// Register CosmosDbToolsService
builder.Services.AddScoped<CosmosDbToolsService>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Customers MCP API v1");
        c.RoutePrefix = string.Empty;
    });
}

app.UseHttpsRedirection();

app.MapControllers();

app.Run();