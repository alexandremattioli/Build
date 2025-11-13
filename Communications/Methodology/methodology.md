# Communication Methodology for Copilot Collaboration

This workflow turns the `K:\Projects\Comms` directory into a lightweight control panel for exchanging information with GitHub Copilot. It keeps the process repeatable, auditable, and easy to evolve.

## 1. Structure
- `copilot_prompt.md`: scratchpad for the actual request you plan to send to Copilot.
- `methodology.md`: living document with process guidance (this file).
- `archive/`: optional folder for dated snapshots of prompts and responses.
- `templates/`: optional folder with reusable prompt snippets (e.g., bug fix, refactor, explain code).

## 2. Daily Loop
1. **Capture goal**  
   - Add a short objective at the top of `copilot_prompt.md` (1–2 sentences).
   - Note any constraints (language, style, files to avoid).
2. **Curate context**  
   - Link or copy code blocks Copilot needs.  
   - Summarize relevant state instead of pasting long logs when possible.
3. **Draft prompt**  
   - Prefer imperative phrasing: “Refactor…”, “Explain…”.  
   - Include success criteria (tests pass, performance target, etc.).
4. **Review before sending**  
   - Quick self-check: is the request unambiguous, scoped, and actionable?  
   - Trim out any secrets or unnecessary paths.
5. **Send via VS Code Copilot Chat**  
   - Copy the final section into Copilot.  
   - Paste the response back into `copilot_prompt.md` under a `## Response` heading.
6. **Reflect & store**  
   - Add a brief note on usefulness or follow-up actions.  
   - Move the prompt/response pair into `archive/YYYY-MM-DD-task.md` when done.

## 3. Prompt Design Checklist
- Clear role: “You are an expert Python developer…”.
- Task focus: single responsibility per prompt. Split large requests.
- Context limit: only the files/code Copilot must see. Mention relative paths.
- Output format: specify `markdown`, `diff`, `checklist`, or `code block`.
- Validation hook: ask Copilot which tests to run or edge cases to watch.

## 4. Versioning & Traceability
- Use git to commit archived prompts for a historical log.  
- Commit messages: `docs(comms): archive copilot prompt for <task>`.  
- Optionally tag milestone exchanges (e.g., `copilot/v1-login-flow`).

## 5. Continuous Improvement
- Review archived interactions weekly to spot prompt patterns that work.  
- Update templates with improved phrasing.  
- Record Copilot limitations you observe and note manual workarounds.

## 6. Security & Privacy
- Never include secrets, access tokens, or proprietary customer data.  
- Redact filenames or sensitive namespaces when context is still clear.  
- Periodically purge the archive if retention policies require it.

Follow this methodology to keep your communication with Copilot consistent, efficient, and audit-friendly.

## Appendix: Watcher Script
- Run `powershell.exe -ExecutionPolicy Bypass -File K:\Projects\Comms\watch_copilot.ps1`.
- Adjust `-Path` to monitor a different file or folder; use `-IntervalSeconds` to change polling cadence.
- When the script prints “Change detected…”, review the prompt and notify Codex so we can help interpret or respond.
