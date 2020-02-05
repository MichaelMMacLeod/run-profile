#!/usr/bin/env racket
; run-profile
; Copyright (C) 2020 Michael MacLeod
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License Version 2 as
; published by the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program; if not, write to the Free Software Foundation, Inc.,
; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

#lang racket

(require racket/cmdline
         (only-in gregor ~t now))

(define commits-to-profile (make-parameter '()))
(define build-commands (make-parameter '()))
(define test-commands (make-parameter '()))
(define number-of-tests (make-parameter 30))
(define cherry-pick-commit (make-parameter #f))
(define filter-command (make-parameter #f))

(define (verify-valid-command-line-arguments)
  (when (empty? (commits-to-profile))
    (raise-user-error "Specify one or more commits or tags with `-c`."))
  (when (empty? (build-commands))
    (raise-user-error "Specify one or more build commands with `-b`."))
  (when (> (length (build-commands))
           (length (commits-to-profile)))
    (raise-user-error "Too many `-b` arguments; specify at most one `-b` per `-c`."))
  (when (empty? (test-commands))
    (raise-user-error "Specify one or more test commands with `-t`."))
  (when (> (length (test-commands))
           (length (commits-to-profile)))
    (raise-user-error "Too many `-t` arguments; specify at most one `-t` per `-c`."))
  (void))

(define (make-profile-directory)
  (define profile-directory
    (format "./profile/~a" (~t (now) "YYYY-MM-dd HH:mm:ss")))
  (make-directory* profile-directory)
  profile-directory)

(define-struct (exn:fail:git:checkout exn:fail:user) (commit git-exit-code))

(define (checkout-commit c)
  (define-values (in out) (make-pipe))
  (define code
    (parameterize ([current-error-port out])
      (system/exit-code (format "git checkout ~a" c))))
  (close-output-port out)
  (unless (= 0 code)
    (raise (make-exn:fail:git:checkout (port->string in)
                                       (current-continuation-marks)
                                       c code)))
  (void))

(define (run-build b)
  (define exit-code
    (system/exit-code b))
  (unless (= 0 exit-code)
    (raise-user-error " => build failed with exit code ~a" exit-code)))

(define (run-test t commit-file)
  (match (filter-command)
    [#f
     (printf " => ~a [output directly to ~a]\n" t commit-file)
     (define exit-code
       (with-output-to-file commit-file
         (lambda ()
           (system/exit-code t))
         #:exists 'append))
     (unless (= 0 exit-code)
       (raise-user-error " => test failed with exit code ~a" exit-code))]
    [filter-command
     (printf " => ~a [output will be filtered through `~a`]\n" t filter-command)
     (define-values (in out) (make-pipe))
     (define test-exit-code
       (parameterize ([current-output-port out])
         (system/exit-code t)))
     (unless (= 0 test-exit-code)
       (raise-user-error " => test failed with exit code ~a" test-exit-code))
     (printf " => filtering output with `~a`\n" filter-command)
     (close-output-port out)
     (define filter-exit-code
       (parameterize ([current-input-port in])
         (with-output-to-file commit-file
           (lambda ()
             (system/exit-code filter-command))
           #:exists 'append)))
     (unless (= 0 filter-exit-code)
       (raise-user-error " => filter failed with exit code ~a" filter-exit-code))]))

(define (verify-commits-can-be-checked-out)
  (with-handlers ([exn:fail:git:checkout?
                   (match-lambda
                     [(and e (exn:fail:git:checkout git-message _ commit exit-code))
                      (printf ":: Error: `git checkout \"~a\"` exited with code ~a\n"
                              commit
                              exit-code)
                      (raise e)])])
    (for ([commit (in-list (commits-to-profile))])
      (checkout-commit commit))
    (when (cherry-pick-commit)
      (checkout-commit (cherry-pick-commit)))))

(define (verify-working-directory-clean)
  (define output
    (with-output-to-string
      (lambda ()
        (system "git status --porcelain --untracked-files=no"))))
  (unless (string=? output "")
    (raise-user-error
     ":: Error: please commit or stash changes in the working directory before continuing")))

(define (hard-reset-head)
  (printf " => git reset --hard HEAD\n")
  (system "git reset --hard HEAD"))

(define (cherry-pick commit)
  (define command (format "git cherry-pick --no-gpg-sign ~a" commit))
  (printf (format " => ~a\n" command))
  (define exit-code (system/exit-code command))
  (unless (= 0 exit-code)
    (raise-user-error
     ":: Error git cherry-pick returned non-zero exit code")))

;; appends the last element of lst onto the end of lst until lst is as big as larger-lst
(define (extend-list lst larger-lst)
  (append lst
          (make-list (- (length larger-lst)
                        (length lst))
                     (last lst))))

(define (run-profile)
  (dynamic-wind
    (lambda ()
      (verify-valid-command-line-arguments)
      (verify-working-directory-clean))
    (lambda ()
      (verify-commits-can-be-checked-out)
      (define profile-directory (make-profile-directory))
      (printf ":: Starting profile [output to ~a]\n" profile-directory)
      (printf ":: This may take a while. You may cancel at any time with Control-c\n")
      (for ([commit (in-list (commits-to-profile))]
            [build-command (extend-list (build-commands) (commits-to-profile))]
            [test-command (extend-list (test-commands) (commits-to-profile))])
        (printf " => git checkout \"~a\"\n" commit)
        (checkout-commit commit)
        (cherry-pick (cherry-pick-commit))
        (printf " => ~a\n" build-command)
        (run-build build-command)
        (for ([n (in-range (number-of-tests))])
          (run-test test-command (build-path profile-directory commit)))))
    (lambda ()
      (printf ":: Profiling completed\n")
      (hard-reset-head))))

(define ((handle-x x) y)
  (x (append (x) (list y))))

(command-line
 #:once-each
 [("-n" "--number-of-tests")
  n
  ("Number of times to call each test function (supplied by `-t`) for each commit"
   "(default is 30).")
  (define rn (string->number n))
  (unless (exact-positive-integer? rn)
    (raise-user-error "`-n` expects an exact positive integer argument"))
  (number-of-tests rn)]
 [("-p" "--cherry-pick")
  commit
  ("After each checkout (of each `-c` commit), and before building (with each `-b`"
   " command), cherry pick a commit onto HEAD. This is useful if profiling code was"
   "added in a later commit than the one being profiled.")
  (cherry-pick-commit commit)]
 [("-f" "--filter-command")
  command
  ("The command which receives the output of each test in its standard input and"
   "whose output is written to the profile at profile/commit_name. If no command"
   "is supplied, the output of the test is written directly to that file.")
  (filter-command command)]
 #:multi
 [("-b" "--build-command")
  command
  ("Commands to build each commit"
   "The first occurrence of `-b` builds the first commit (specified by `-c`),"
   "the second build command is used to build the second commit,"
   "and so on. The last build command is used to build all of the other"
   "commits (when there are more commits than build commands)"
   "Example: ./run-profile.rkt -b 'make clean && npm run web' -c a1b2d3 -c e4f5"
   "  uses one build command to build two commits."
   "Example: ./run-profile.rkt -b 'make buildFirst' -c a1b2d3 -b 'make buildSecond' -c e4f5"
   "  uses two build commands; the first builds commit ab1b2d3 and the second builds e4f5.")
  ((handle-x build-commands) command)]
 [("-t" "--test-command")
  command
  ("Commands to test each commit"
   "Can be specified more than once, like `-b`.")
  ((handle-x test-commands) command)]
 [("-c" "--commit")
  commit-or-tag
  "Run a profile on a commit or git tag (on the current branch)"
  ((handle-x commits-to-profile) commit-or-tag)])

(run-profile)
