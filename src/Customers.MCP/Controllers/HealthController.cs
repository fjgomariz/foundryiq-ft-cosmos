using Microsoft.AspNetCore.Mvc;

namespace Customers.MCP.Controllers;

[ApiController]
[Route("[controller]")]
public class HealthController : ControllerBase
{
    /// <summary>
    /// Checks if the application is healthy
    /// </summary>
    /// <returns>Returns "ok" if the application is healthy</returns>
    /// <response code="200">Application is healthy</response>
    [HttpGet("healthy")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult Healthy()
    {
        return Ok("ok");
    }

    /// <summary>
    /// Checks if the application is ready to accept requests
    /// </summary>
    /// <returns>Returns "ok" if the application is ready</returns>
    /// <response code="200">Application is ready</response>
    [HttpGet("ready")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult Ready()
    {
        return Ok("ok");
    }
}
