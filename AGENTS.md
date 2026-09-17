# Agent instructions

## This repository is public

It is open source and readable by anyone. Everything committed here — code, comments, tests,
README, commit messages, PR titles and descriptions, issue text, branch names — is published the
moment it is pushed, and stays published: a later commit does not remove it from the history, and
a force-push does not remove it from forks, clones, mirrors or anything that has already fetched.

**Assume every word you write here will be read by someone outside the company.** If something
would need an explanation before you'd show it to a stranger, it does not go in.

## What must not appear

**Anything naming or describing our own systems.** Internal application, service, repository or
database names; internal endpoint paths; internal field, column or table names; file paths from
another repository; internal URLs, hostnames or dashboards.

**Anything about our customers.** Names, domains, account or project identifiers, data samples,
and the size or shape of anyone's usage — including figures that are merely *about* customers
rather than from them.

**Anything from our private repositories.** Issue and PR numbers, links, ticket identifiers,
quoted discussion, and the internal reasoning behind a change. Cross-references to a private repo
are a link to a 404 for everyone outside the company and a description of our internals for
everyone inside it.

**Measurements taken against our own codebase.** "14 of 129 endpoints failed" reads as a neutral
statistic and is in fact a map of how large our API is and how much of it is wrong. Describe the
*kind* of problem the change surfaces, never the count.

**Incident detail.** How long a bug went unnoticed, what it cost, who noticed it, which release
introduced it.

**Credentials and machine identity of any kind**, including things that look harmless: session
identifiers, trace or request ids, internal tokens, agent session links. Keep the
`Co-Authored-By:` trailer if you use one; drop any trailer carrying a session or transcript URL.

## What belongs here instead

Write for a reader who has never heard of us and is evaluating whether to use the gem.

- **Motivate with the failure, not with our incident.** "A client misspells a field, the endpoint
  ignores it, the response is a 200" is the same lesson without the postmortem.
- **Use invented examples.** `articles`, `name`, `status`, `description` — the vocabulary already
  used throughout the README. Never paste a real payload, even a redacted one; a redacted payload
  still publishes its shape.
- **Explain design decisions on their own terms.** Why a default is what it is, what it costs to
  adopt, which cases are deliberately excluded. That is what an outside reader needs and it
  happens to contain nothing internal.

## Before you push

Re-read the diff, the commit message and the PR description as three separate documents, because
they leak independently and only the first one gets reviewed carefully. Ask of each: *does this
name anything of ours, quote anything private, or count anything?*

When the honest explanation of a change cannot be given without internal context, publish the
generic version here and keep the specifics in the private repository that has them.
