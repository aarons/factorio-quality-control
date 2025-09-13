Please evaluate the comments recently added; we only want code comments that explain things that are not knoweable outside the codebase, such as design decisions, how an API works, or evaluations or unexpected patterns that we need to retain to not backtrack on later.

Occasionally we may document how something works when it's unclear; this is ok to leave.

Some types of code comments to remove:
- anything that references removed code when it's not relevant to existing code (ie, "removed function" "replaced the old with a new algorithm" etc. )
- steam of consciousness type comments
- things that are very obvious: "# Run pytest on ..." or "Function to validate ..." when the function is literally named "validate_..."

$ARGUMENTS