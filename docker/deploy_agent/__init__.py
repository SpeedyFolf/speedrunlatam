"""In-container deployment agent for Speedrun LATAM.

The agent is intentionally small: it downloads and validates a release
bundle, takes a safety snapshot of the runtime data, applies files and
reports a plan.  The Pterodactyl panel (driven by GitHub Actions) is the
only component that sends console commands to MTA.

See docs/cd.md for the full contract.
"""

__version__ = "1.0.0"
