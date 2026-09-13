namespace SCAA_Final_Web
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            builder.Services.AddControllersWithViews();
            builder.Services.AddHealthChecks();
            builder.Logging.ClearProviders();
            builder.Logging.AddSimpleConsole(options =>
            {
                options.SingleLine = true;
                options.TimestampFormat = "yyyy-MM-dd HH:mm:ss ";
            });


            var app = builder.Build();

            if (!app.Environment.IsDevelopment())
                app.UseExceptionHandler("/Home/Error");
            app.UseRouting();
            app.UseAuthorization();
            app.MapStaticAssets();
            app.MapHealthChecks("/health");
            app.MapGet("/version", () => Results.Json(new
            {
                application = "SCAA-Final-Web",
                version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "local",
                host = Environment.MachineName,
                utcTime = DateTime.UtcNow
            }));
            app.MapControllerRoute(
                name: "default",
                pattern: "{controller=Home}/{action=Index}/{id?}")
                .WithStaticAssets();
            app.Run();
        }
    }
}
