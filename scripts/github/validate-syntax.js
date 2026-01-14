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
    if (inQuote) {
      throw new Error(`Unclosed quote: expected closing ${quoteChar}`);
    }
    return args;
  }

  let error = null;
  let cmd = null;
  let args = [];

  try {
    const tokens = parseArgs(line.trim());
    cmd = tokens[0];
    args = tokens.slice(1);
  } catch (err) {
    error = err.message || 'Invalid command syntax.';
  }

  console.log(`Command: ${cmd}, Args: ${JSON.stringify(args)}`);

  if (!error) {
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
      case '/clean':
        if (args.length !== 1) error = "Usage: `/clean <field>`";
        break;
      case '/list-config':
        if (args.length > 0) error = "Usage: `/list-config` (no arguments)";
        break;
      default:
        // Should be caught by 'if', but just in case
        error = `Unknown command: ${cmd}`;
    }
  }

  if (error) {
    console.log("Validation failed:", error);

    // Report failure
    const failBody = `### ⚠️ ChatOps Syntax Error

    **Command:** \`${line}\`
    **Error:** ${error}

    **Usage Guide:**
    - \`/set-bin <exe> [alias]\` (Appends if exists)
    - \`/set-shortcut <name> (auto-detect target)\` (Appends if exists)
    - \`/set-shortcut <target> <name>\` (Appends if exists)
    - \`/set-persist <file> [alias]\` (Appends if exists)
    - \`/set-key <key> <value>\`
    - \`/clean <field>\`
    - \`/list-config\`
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
