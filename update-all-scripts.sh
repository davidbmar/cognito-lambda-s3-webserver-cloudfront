#!/bin/bash
# update-all-scripts.sh - Updates all step scripts to use common sequence functions

set -e

echo "🔄 Updating all step scripts to use common sequence functions..."

# List of scripts to update
scripts=(
    "step-10-setup.sh"
    "step-15-validate.sh"
    "step-20-deploy.sh"
    "step-22-update-cognito-client.sh"
    "step-30-create-user.sh"
    "step-40-test.sh"
    "step-45-setup-audio.sh"
    "step-47-validate-audio.sh"
)

# Create backup directory
mkdir -p script-backups

# Update each script
for script in "${scripts[@]}"; do
    if [[ -f "$script" ]]; then
        echo "📝 Updating $script..."
        
        # Create backup
        cp "$script" "script-backups/${script}.bak"
        
        # Create temporary file with updates
        temp_file=$(mktemp)
        
        # Read the script and make modifications
        awk '
        BEGIN { 
            source_added = 0
            in_header = 1
        }
        
        # Add source line after shebang and comments
        /^#!/ { print; next }
        /^#/ && in_header { print; next }
        
        # First non-comment line - add source
        !/^#/ && !source_added {
            in_header = 0
            if ($0 ~ /^set -e/) {
                print
                print ""
                print "# Source the common sequence functions"
                print "source ./script-sequence.sh"
                source_added = 1
                next
            } else {
                print "set -e # Exit on any error"
                print ""
                print "# Source the common sequence functions"
                print "source ./script-sequence.sh"
                print ""
                source_added = 1
            }
        }
        
        # Skip old source .env lines
        /source \.env/ { next }
        /\. \.env/ { next }
        
        # Replace env file checks with load_config
        /if \[ ! -f \.env \]/ {
            print "# Load configuration using common function"
            print "if ! load_config; then"
            print "    exit 1"
            print "fi"
            # Skip the error message and fi
            getline; getline; getline; getline
            next
        }
        
        # Add print_script_purpose after welcome banner
        /echo$/ && /===/ {
            print
            getline
            if ($0 ~ /^echo$/) {
                print
                print "# Display what this script does"
                print "print_script_purpose"
            } else {
                print
            }
            next
        }
        
        # Print other lines
        { print }
        
        END {
            # Add update_setup_status and print_next_steps at the end
            print ""
            print "# Update setup status"
            print "update_setup_status"
            print ""
            print "# Print next steps using common function"
            print "print_next_steps"
        }
        ' "$script" > "$temp_file"
        
        # Replace original with updated version
        mv "$temp_file" "$script"
        chmod +x "$script"
        
        echo "✅ Updated $script"
    else
        echo "⚠️  Skipping $script (not found)"
    fi
done

echo ""
echo "✅ All scripts updated successfully!"
echo "📁 Backups saved in script-backups/"
echo ""
echo "Note: The updates include:"
echo "  - Source script-sequence.sh for common functions"
echo "  - Use load_config() instead of direct source .env"
echo "  - Add print_script_purpose() after banner"
echo "  - Add update_setup_status() before completion"
echo "  - Add print_next_steps() at the end"