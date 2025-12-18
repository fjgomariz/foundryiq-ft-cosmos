using Microsoft.Azure.Cosmos;
using System.Text.Json;
using Azure.Identity;
using System.Text.RegularExpressions;
using Azure.AI.OpenAI;

namespace AzureCosmosDB.MCP.Toolkit.Services;

public class CosmosDbToolsService
{
    private readonly CosmosClient _cosmosClient;
    private readonly ILogger<CosmosDbToolsService> _logger;
    private readonly IConfiguration _configuration;

    public CosmosDbToolsService(
        CosmosClient cosmosClient, 
        ILogger<CosmosDbToolsService> logger,
        IConfiguration configuration)
    {
        _cosmosClient = cosmosClient ?? throw new ArgumentNullException(nameof(cosmosClient));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
    }
    
    // Helper method to validate required parameter
    private void ValidateRequiredParameter(string value, string paramName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"Parameter '{paramName}' is required.", paramName);
        }
    }


    public async Task<object> GetRecentDocuments(string databaseId, string containerId, int n, CancellationToken cancellationToken = default)
    {
        try
        {
            ValidateRequiredParameter(databaseId, nameof(databaseId));
            ValidateRequiredParameter(containerId, nameof(containerId));
            
            if (n < 1 || n > 20)
            {
                return new { error = "Parameter 'n' must be a whole number between 1 and 20." };
            }

            _logger.LogInformation("Getting {Count} recent documents from {DatabaseId}/{ContainerId}", n, databaseId, containerId);

            var container = _cosmosClient.GetContainer(databaseId, containerId);
            var queryText = $"SELECT TOP {n} * FROM c ORDER BY c._ts DESC";
            
            using var streamIterator = container.GetItemQueryStreamIterator(
                new QueryDefinition(queryText),
                requestOptions: new QueryRequestOptions { MaxItemCount = n }
            );

            var results = new List<System.Text.Json.JsonElement>();
            while (streamIterator.HasMoreResults && results.Count < n)
            {
                using var response = await streamIterator.ReadNextAsync(cancellationToken);
                using var stream = response.Content;
                using var document = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
                
                var documents = document.RootElement.GetProperty("Documents");
                foreach (var doc in documents.EnumerateArray())
                {
                    results.Add(doc.Clone());
                    if (results.Count >= n) break;
                }
            }

            _logger.LogInformation("Successfully retrieved {Count} recent documents", results.Count);
            return results;
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning(ex, "Invalid parameter: {Message}", ex.Message);
            return new { error = ex.Message };
        }
        catch (CosmosException cex)
        {
            _logger.LogError(cex, "Cosmos DB error getting recent documents: {StatusCode}", cex.StatusCode);
            return new { error = cex.Message, statusCode = (int)cex.StatusCode };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting recent documents");
            return new { error = ex.Message };
        }
    }

    public async Task<object> FindDocumentByID(string databaseId, string containerId, string id, CancellationToken cancellationToken = default)
    {
        try
        {
            ValidateRequiredParameter(databaseId, nameof(databaseId));
            ValidateRequiredParameter(containerId, nameof(containerId));
            ValidateRequiredParameter(id, nameof(id));

            _logger.LogInformation("Finding document by ID {Id} in {DatabaseId}/{ContainerId}", id, databaseId, containerId);

            var container = _cosmosClient.GetContainer(databaseId, containerId);
            var queryText = "SELECT * FROM c WHERE c.id = @id";
            var query = new QueryDefinition(queryText).WithParameter("@id", id);

            using var streamIterator = container.GetItemQueryStreamIterator(
                query,
                requestOptions: new QueryRequestOptions { MaxItemCount = 1 }
            );

            while (streamIterator.HasMoreResults)
            {
                using var response = await streamIterator.ReadNextAsync(cancellationToken);
                using var stream = response.Content;
                using var document = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
                
                var documents = document.RootElement.GetProperty("Documents");
                if (documents.GetArrayLength() > 0)
                {
                    _logger.LogInformation("Document found with ID {Id}", id);
                    return documents[0].Clone();
                }
            }

            _logger.LogInformation("No document found with ID {Id}", id);
            return new { message = "No document found with the specified id." };
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning(ex, "Invalid parameter: {Message}", ex.Message);
            return new { error = ex.Message };
        }
        catch (CosmosException cex)
        {
            _logger.LogError(cex, "Cosmos DB error finding document: {StatusCode}", cex.StatusCode);
            return new { error = cex.Message, statusCode = (int)cex.StatusCode };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error finding document");
            return new { error = ex.Message };
        }
    }

}