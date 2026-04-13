// Shared comment-parsing logic for terraform-plan.yml and
// terraform-apply.yml. Called from actions/github-script steps.
//
// Targets must be wrapped in single quotes to clearly delimit the
// address, e.g.: plan -target='cloudflare_dns_record.com_root'
//
// This supports all Terraform address forms including module paths,
// data sources, and indexed resources:
//   -target='type.name'
//   -target='type.name[0]'
//   -target='type.name["key"]'
//   -target='module.name.type.name'
//   -target='data.type.name'
//
// The allowlist inside quotes blocks shell metacharacters while
// accepting any realistic Terraform address character.

module.exports = async function parseTargets({github, context, core, heading}) {
  const comment = context.payload.comment.body.trim();
  const match = comment.match(/^(plan|apply)((?:\s+-target='[^']*')*)\s*$/);
  if (!match) {
    const runUrl = `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`;
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: context.issue.number,
      body: `## Terraform ${heading}\n\n`
        + ':x: Unrecognized command format.\n\n'
        + 'Expected one of:\n'
        + '- `plan`\n'
        + '- `plan -target=\'resource_type.name\'`\n'
        + '- `apply`\n'
        + '- `apply -target=\'resource_type.name\'`\n\n'
        + 'Targets must use `-target=` (hyphen, not equals) and be wrapped in single quotes.\n\n'
        + '---\n*[View workflow run](' + runUrl + ')*'
    });
    core.setFailed('Comment does not match expected command format');
    return;
  }

  const targetString = match[2].trim();
  const targets = [];

  if (targetString) {
    // Allow letters, digits, underscores, dots, brackets, double
    // quotes, hyphens, and colons. Must start with a letter and
    // contain at least one dot. Blocks all shell metacharacters
    // (;|&$`(){}<>\!#' and whitespace).
    const targetPattern = /^[a-zA-Z][a-zA-Z0-9_.\[\]":-]*\.[a-zA-Z0-9_.\[\]":-]*[a-zA-Z0-9_\]"]$/;

    for (const flag of targetString.match(/-target='[^']*'/g) || []) {
      const addr = flag.replace(/^-target='/, '').replace(/'$/, '');
      if (!addr || !targetPattern.test(addr)) {
        const safeAddr = addr.slice(0, 100);
        const runUrl = `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`;
        await github.rest.issues.createComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: context.issue.number,
          body: `## Terraform ${heading}\n\n`
            + `:x: Invalid target address: \`${safeAddr}\`\n\n`
            + 'Target addresses must be wrapped in single quotes and contain only '
            + 'letters, digits, underscores, dots, brackets, double quotes, '
            + 'hyphens, and colons.\n\n'
            + 'Example: `plan -target=\'cloudflare_dns_record.com_root\'`\n\n'
            + '---\n*[View workflow run](' + runUrl + ')*'
        });
        core.setFailed(`Invalid target address: ${safeAddr}`);
        return;
      }
      targets.push(addr);
    }
    if (targets.length > 10) {
      const runUrl = `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`;
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: context.issue.number,
        body: `## Terraform ${heading}\n\n`
          + `:x: Too many targets (${targets.length}). Maximum is 10.\n\n`
          + '---\n*[View workflow run](' + runUrl + ')*'
      });
      core.setFailed(`Too many targets: ${targets.length} (max 10)`);
      return;
    }
  }

  const targetFlags = targets.map(t => `-target=${t}`).join(' ');
  core.setOutput('targets', targetFlags);
  core.setOutput('target_list', targets.join(', '));
  core.setOutput('is_targeted', targets.length > 0 ? 'true' : 'false');
};
