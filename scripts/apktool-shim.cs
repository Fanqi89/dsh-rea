using System;
using System.Diagnostics;
using System.Text;

// apktool.exe shim for REA on Windows.
// REA starts the launcher through shell-free execFile, so a .bat/.cmd wrapper
// cannot be started directly (execFile neither resolves nor runs batch files).
// This console program forwards every argument to `java -jar apktool.jar`,
// pumps the child's stdout/stderr to the inherited handles, and returns the
// child's exit code, so REA can read `<launcher> --version` and `<launcher> d ...`.
//
// scripts/setup-rea-tools.ps1 replaces the two placeholders below with the
// detected java.exe and the downloaded apktool jar before compiling this file.
public class ApktoolShim
{
    private const string Java = @"__JAVA__";
    private const string Jar = @"__JAR__";

    private static string Quote(string value)
    {
        if (value.Length == 0) return "\"\"";
        var sb = new StringBuilder("\"");
        var backslashes = 0;
        foreach (var ch in value)
        {
            if (ch == '\\') { backslashes++; sb.Append(ch); continue; }
            if (ch == '"')
            {
                sb.Append('\\', backslashes * 2 + 1);
                sb.Append('"');
                backslashes = 0;
                continue;
            }
            sb.Append(ch);
            backslashes = 0;
        }
        sb.Append('\\', backslashes * 2);
        sb.Append('"');
        return sb.ToString();
    }

    public static int Main(string[] args)
    {
        var commandLine = new StringBuilder("-jar ").Append(Quote(Jar));
        foreach (var argument in args) commandLine.Append(' ').Append(Quote(argument));

        var startInfo = new ProcessStartInfo(Java, commandLine.ToString());
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;

        using (var process = Process.Start(startInfo))
        {
            var stdout = process.StandardOutput.BaseStream.CopyToAsync(Console.OpenStandardOutput());
            var stderr = process.StandardError.BaseStream.CopyToAsync(Console.OpenStandardError());
            process.WaitForExit();
            stdout.Wait();
            stderr.Wait();
            return process.ExitCode;
        }
    }
}
