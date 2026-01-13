module.exports = async ({ github, context, core }) => {
  const body = context.payload.comment.body;
  // Get first line starting with /
  const line = body.split('\n').find(l => l.trim().startsWith('/'));
  if (!line) return;

  // Simple parser for quoted args
  function parseArgs(str) {
    const args = [];
    let current = '';
    let inQuote = false;
    let quoteChar = '';
    
    for (let i = 0; i < str.length; i++) {
      const char = str[i];
      if (inQuote) {
        if (char === quoteChar) {
          inQuote = false;
        } else {
          current += char;
        }
      } else {
        if (char === '"' || char === "'") {
          inQuote = true;
          quoteChar = char;
        } else if (/\s/.test(char)) {
          if (current) {
            args.push(current);
            current = '';
          }
        } else {
          current += char;
        }
      }
    }
    if (current) args.push(current);
    return args;
  }

  const tokens = parseArgs(line.trim());
  const cmd = tokens[0];
  const args = tokens.slice(1);
  let error = null;

  console.log(`Command: ${cmd}, Args: ${JSON.stringify(args)}`);

  switch (cmd) {
    case '/set-bin':
      if (args.length < 1 || args.length > 2) error = "Usage: `/set-bin <exe> [alias]`";
      break;
    case '/set-shortcut':
      if (args.length < 1 || args.length > 2) error = "Usage: `/set-shortcut <name>` (auto) OR `/set-shortcut <target> <name>`";
      break;
    case '/set-persist':
      if (args.length < 1 || args.length > 2) error = "Usage: `/set-persist <file> [alias]`";
      break;
    case '/set-key':
      if (args.length < 2) error = "Usage: `/set-key <key> <value>`";
      break;
    default:
      // Should be caught by 'if', but just in case
      error = `Unknown command: ${cmd}`;
  }

  if (error) {
    console.log("Validation failed:", error);
    
    // Report failure
    const failBody = `### ⚠️ ChatOps Syntax Error
    
    **Command:** \`${line}\`
    **Error:** ${error}

    **Usage Guide:**
    - \`/set-bin <exe> [alias]\`
    - \`/set-shortcut <name> (auto-detect target)\`
    - \`/set-shortcut <target> <name>\`
    - \`/set-persist <file> [alias]\`
    - \`/set-key <key> <value>\`
    `;

    await github.rest.issues.createComment({
      issue_number: context.issue.number,
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: failBody
    });

    await github.rest.reactions.createForIssueComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: context.payload.comment.id,
      content: 'confused'
    });

    core.setFailed(error);
  } else {
    console.log("Syntax check passed.");
  }
};
