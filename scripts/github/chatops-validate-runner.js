const path = require('path');

module.exports = async ({ github, context, core }) => {
  if (context.eventName === 'workflow_dispatch') {
    const body =
      process.env.COMMENT_BODY ||
      (context.payload.inputs && context.payload.inputs.comment_body) ||
      '';
    const prNumberRaw =
      process.env.PR_NUMBER ||
      (context.payload.inputs && context.payload.inputs.pr_number) ||
      '';
    const prNumber = parseInt(prNumberRaw, 10);

    if (!prNumber) {
      core.setFailed('Missing PR number for workflow_dispatch.');
      return;
    }

    context.payload.comment = { body, id: 1 };
    Object.defineProperty(context, 'issue', {
      get: () => ({
        owner: context.repo.owner,
        repo: context.repo.repo,
        number: prNumber
      })
    });
    github.rest.reactions.createForIssueComment = async (args) => {
      console.log(`[Mock] Adding reaction ${args.content} to comment ${args.comment_id}`);
      return { data: {} };
    };
  }

  const fullPath = path.join(
    process.env.GITHUB_WORKSPACE || '.',
    './scripts/github/validate-syntax.js'
  );
  const script = require(fullPath);
  await script({ github, context, core });
};
