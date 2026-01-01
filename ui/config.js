// This file is overwritten by scripts/quick_launch.ps1 to point the UI at the
// dynamically chosen API port. The fallback keeps local development working
// even if the quick launch script is not used.
window.BONSAI_API_BASE = window.BONSAI_API_BASE || "http://localhost:8010";
