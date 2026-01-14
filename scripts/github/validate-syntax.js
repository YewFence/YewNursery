module.exports = async ({ github, context, core }) => {
  const fs = require('fs');
  const path = require('path');
  
  // Load command definitions
  const configPath = path.join(process.env.GITHUB_WORKSPACE || '.', 'scripts/config/chatops-commands.json');
  let commands = {};
  try {
    commands = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (e) {
    console.error(`Failed to load command config from ${configPath}:`, e);
    // Fallback or fail? Failing is safer to prevent executing unknown logic.
    core.setFailed(`Configuration Error: Could not load chatops-commands.json. ${e.message}`);
    return;
  }

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
    const commandConfig = commands[cmd];
    
    if (!commandConfig) {
      error = `Unknown command: ${cmd}`;
    } else {
      const { minArgs, maxArgs, usage } = commandConfig;
      
      if (minArgs !== null && minArgs !== undefined && args.length < minArgs) {
        error = `Usage: \`${usage}\``;
      } else if (maxArgs !== null && maxArgs !== undefined && args.length > maxArgs) {
        error = `Usage: \`${usage}\``;
      }
    }
  }

  if (error) {
    console.log("Validation failed:", error);

    // Report failure
    const usageGuide = fs.readFileSync('scripts/templates/chatops-usage-guide.md', 'utf8');
    const failBody = `### ⚠️ ChatOps Syntax Error

    **Command:** \`${line}\`
    **Error:** ${error}

    ${usageGuide}
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
