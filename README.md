run-profile
===========

run-profile.rkt is a command-line application for profiling different versions 
of a project that uses git for version control. It uses a user-supplied test 
function like `make test` to do the profiling.

run-profile.rkt works in roughly this manner:

1. creates the directory ./profile/YYYY-MM-dd HH:mm:ss/
2. checks out the commit supplied by the first occurrence of `--commit <commit-or-tag>`
3. cherry-picks the commit specified by `--cherry-pick <commit>` onto HEAD
4. runs the command specified by the first occurrence of `--build-command <command>`
5. runs the command specified by `--test-command <command>`
6. sends the standard output of (5) to the command specified by `--filter-command <command>`
7. appends the standard output of (6) to ./profile/YYYY-MM-dd HH:mm:ss/<commit>
8. repeats steps (5) through (7) `--number-of-tests <n>` times
9. repeats steps (2) through (8) for the rest of the commits specified by `--commit <commit-or-tag>`

### Example

```sh
$ ./run-profile.rkt \
      -b 'make clean && npm i && make' \   # the first commit will be built with this command
      -b 'npm i && make' \                 # the rest of the commits will be built using this command
      -c h_f_e -c h_e_no_f -c h_no_e_f \   # these are the commit (tags) which will be profiled
      -t 'make type-check-test' \          # the command to run tests
      -n 15 \                              # run 15 tests (instead of the default 30)
      -p horizon_type_check_time_logging \ # cherry-pick this commit before building
      -f ./filter-horizon-output.sh        # filter test output through this command
```

### Usage
```sh
$ ./run-profile.rkt --help
run-profile.rkt [ <option> ... ]
 where <option> is one of
  -n <n>, --number-of-tests <n> : Number of times to call each test function (supplied by `-t`) for each commit
    (default is 30).
  -p <commit>, --cherry-pick <commit> : After each checkout (of each `-c` commit), and before building (with each `-b`
     command), cherry pick a commit onto HEAD. This is useful if profiling code was
    added in a later commit than the one being profiled.
  -f <command>, --filter-command <command> : The command which receives the output of each test in its standard input and
    whose output is written to the profile at profile/commit_name. If no command
    is supplied, the output of the test is written directly to that file.
* -b <command>, --build-command <command> : Commands to build each commit
    The first occurrence of `-b` builds the first commit (specified by `-c`),
    the second build command is used to build the second commit,
    and so on. The last build command is used to build all of the other
    commits (when there are more commits than build commands)
    Example: ./run-profile.rkt -b 'make clean && npm run web' -c a1b2d3 -c e4f5
      uses one build command to build two commits.
    Example: ./run-profile.rkt -b 'make buildFirst' -c a1b2d3 -b 'make buildSecond' -c e4f5
      uses two build commands; the first builds commit ab1b2d3 and the second builds e4f5.
* -t <command>, --test-command <command> : Commands to test each commit
    Can be specified more than once, like `-b`.
* -c <commit-or-tag>, --commit <commit-or-tag> : Run a profile on a commit or git tag (on the current branch)
  --help, -h : Show this help
  -- : Do not treat any remaining argument as a switch (at this level)
 * Asterisks indicate options allowed multiple times.
 Multiple single-letter switches can be combined after one `-'; for
  example: `-h-' is the same as `-h --'
```
