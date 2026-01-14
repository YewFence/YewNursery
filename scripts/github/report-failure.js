module.exports = async ({ github, context, core }) => {
  const fs = require('fs');
  const logFile = process.env.LOG_FILE || 'chatops.log';
  let log = '';

  try {
    // Try to read the log file if it exists
    if (fs.existsSync(logFile)) {
      log = fs.readFileSync(logFile, 'utf8');
    } else {
      log = 'Log file not found. Please check Action logs.';
    }
  } catch (e) {
    log = `Error reading log: ${e.message}`;
  }

  // Truncate log if too long (Github comment limit is ~65k chars, but let's keep it shorter)
  if (log.length > 2000) {
    log = log.substring(0, 2000) + '\n... (truncated)';
  }

  const usageGuide = fs.readFileSync('scripts/templates/chatops-usage-guide.md', 'utf8');

  const body = `### ❌ ChatOps Command Failed

**Error Details:**
\`\`\`text
${log}
\`\`\`

${usageGuide}

[View Action Log](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})
`;

  try {
    await github.rest.issues.createComment({
      issue_number: context.issue.number,
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: body
    });

    await github.rest.reactions.createForIssueComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: context.payload.comment.id,
      content: 'confused'
    });
  } catch (error) {
    console.error('Failed to send failure report:', error);
  }
};
