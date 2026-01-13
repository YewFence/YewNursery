module.exports = async ({ github, context, core }) => {
  const fs = require('fs');
  const reportFile = process.env.REPORT_FILE || 'chatops-report.md';
  let body = '';

  try {
    // Try to read the report file if it exists
    if (fs.existsSync(reportFile)) {
      body = fs.readFileSync(reportFile, 'utf8');
    } else {
      // Fallback if report missing but step succeeded (shouldn't happen)
      body = '### ✅ ChatOps Applied\n\nCommand executed successfully, but report generation failed.';
    }
  } catch (e) {
    body = `### ✅ ChatOps Applied\n\nError reading report: ${e.message}`;
  }

  // Add log link footer
  body += `\n\n[View Action Log](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})`;

  try {
    // 1. Add Rocket Reaction
    await github.rest.reactions.createForIssueComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: context.payload.comment.id,
      content: 'rocket'
    });

    // 2. Post Comment
    await github.rest.issues.createComment({
      issue_number: context.issue.number,
      owner: context.repo.owner,
      repo: context.repo.repo,
      body: body
    });

    console.log("Posted success report.");
  } catch (error) {
    console.error('Failed to send success report:', error);
  }
};
