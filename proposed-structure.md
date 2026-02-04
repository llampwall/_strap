Proposed Module Structure

  P:\software\_strap\
  ├── strap.ps1              # Main entry point (CLI parser + command dispatch) ~500 lines
  ├── modules\
  │   ├── Core.ps1           # Utilities, logging, command checks
  │   ├── Config.ps1         # Config/registry load/save/validate
  │   ├── Chinvex.ps1        # All chinvex integration
  │   ├── Path.ps1           # Path normalization and validation
  │   ├── Git.ps1            # Git operations and repo management
  │   ├── Template.ps1       # Template processing engine
  │   ├── Process.ps1        # Process management utilities
  │   ├── Audit.ps1          # Audit index and reference scanning
  │   ├── Commands\
  │   │   ├── List.ps1       # Invoke-List
  │   │   ├── Open.ps1       # Invoke-Open
  │   │   ├── Move.ps1       # Invoke-Move, Invoke-Rename
  │   │   ├── Shim.ps1       # Invoke-Shim (your new shim system fits here!)
  │   │   ├── Setup.ps1      # Invoke-Setup
  │   │   ├── Update.ps1     # Invoke-Update
  │   │   ├── Uninstall.ps1  # Invoke-Uninstall
  │   │   ├── Doctor.ps1     # Invoke-Doctor
  │   │   ├── Adopt.ps1      # Invoke-Adopt
  │   │   └── Templatize.ps1 # Invoke-Templatize
  │   └── Migrations.ps1     # All migration logic
  └── tests\                 # Existing test structure