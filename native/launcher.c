// MechCommander 2 launcher stub: a Mach-O main executable that execs the
// real bash launcher beside it (notarization requires a Mach-O main
// executable, not a script). argv/env are passed through unchanged.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <mach-o/dyld.h>

int main(int argc, char **argv, char **envp)
{
    char exe[4096];
    uint32_t size = (uint32_t)sizeof(exe);
    if (_NSGetExecutablePath(exe, &size) != 0) {
        fprintf(stderr, "launcher: cannot resolve executable path\n");
        return 127;
    }

    char script[4096];
    snprintf(script, sizeof(script), "%s/../Resources/MechCommander2.sh", dirname(exe));

    char **new_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (!new_argv)
        return 127;
    new_argv[0] = script;
    for (int i = 1; i < argc; ++i)
        new_argv[i] = argv[i];

    execve(script, new_argv, envp);
    perror("launcher: execve failed");
    return 127;
}
