/**
 * Oma executable entrypoint.
 *
 * Keeps `main` minimal so all logic in `oma.*` remains cleanly testable under `dub test`.
 * Under `version (unittest)`, an empty `main` lets D's built-in unittest runner execute
 * all module `unittest` blocks cleanly without entering the CLI loop.
 *
 * Spec_Ref: https://dlang.org/spec/function.html#main
 * Spec_Ref: https://dlang.org/spec/unittest.html
 */
module app;

import oma.cli : run;

version (unittest)
{
    void main()
    {
    }
}
else
{
    int main(string[] args)
    {
        return run(args);
    }
}
