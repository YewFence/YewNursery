module.exports = async ({ github, context, core }) => {
  const reaction = process.env.REACTION_CONTENT;
  if (!reaction) {
    console.log('No reaction content specified in REACTION_CONTENT env var.');
    return;
  }

  try {
    await github.rest.reactions.createForIssueComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: context.payload.comment.id,
      content: reaction
    });
    console.log(`Added '${reaction}' reaction.`);
  } catch (error) {
    console.error('Failed to add reaction:', error);
  }
};
