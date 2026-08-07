//! Interactive confirmation, matching the bash version's semantics: an
//! explicit y/n wins, anything else (including empty or EOF) takes the
//! default. Works with piped stdin so tests can drive the prompts.

use std::io::{BufRead, Write};

use anyhow::Result;

pub fn confirm(question: &str, default: bool) -> Result<bool> {
    let suffix = if default { "[Y/n]" } else { "[y/N]" };
    print!("{question} {suffix} ");
    std::io::stdout().flush()?;

    let mut line = String::new();
    let read = std::io::stdin().lock().read_line(&mut line)?;
    if read == 0 {
        // EOF (e.g. exhausted pipe): take the default, keep output tidy.
        println!();
        return Ok(default);
    }
    let answer = line.trim();
    Ok(
        if answer.eq_ignore_ascii_case("y") || answer.eq_ignore_ascii_case("yes") {
            true
        } else if answer.eq_ignore_ascii_case("n") || answer.eq_ignore_ascii_case("no") {
            false
        } else {
            default
        },
    )
}
