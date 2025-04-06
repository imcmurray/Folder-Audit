# This will create individual html files for each user,
# allowing them to expand/collapse folders in the tree structure.
# Once expanded, each folder will allow the user to select an 
# appropriate actions, such as: Keep, Archive or Delete.
# At the bottom there will be a submit button which will send their
# decisions to the server for processing. The data will be stored in
# JSON format in CouchDB, which will be used to generate a report
# for folders to be archived and deleted. 

# Define the input file (replace with your actual file name)
$inputFile = "dir-example.txt"

# Array to store folder details
$output = @()

# Variable to track the current directory
$currentDir = $null

# Regex for folder lines
$folderRegex = "^(\d{2}/\d{2}/\d{4})\s+(\d{2}:\d{2}\s+[AP]M)\s+(?:<DIR>\s+)?\s*(\S+\\[^\s]+)\s+([^\s].*)$"

# Process the input file line by line
Get-Content $inputFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -match "^\s*Directory of (.+)$") {
        $currentDir = $matches[1].Trim()
    }
    elseif ($currentDir -and $line -match $folderRegex) {
        $date = $matches[1]
        $time = $matches[2]
        $owner = $matches[3]
        $folderName = $matches[4]
        if ($folderName -notin @('.', '..')) {
            $fullPath = "$currentDir\$folderName"
            $output += [PSCustomObject]@{
                User     = $owner
                FullPath = $fullPath
                Date     = "$date $time"
            }
        }
    }
}

# Group the output by user
$grouped = $output | Group-Object User

# Function to build a folder tree from a list of paths
function BuildTree($paths) {
    $tree = @{}
    foreach ($path in $paths) {
        $parts = $path.FullPath -split '\\'
        $current = $tree
        for ($i = 0; $i -lt $parts.Length; $i++) {
            $part = $parts[$i]
            $fullPathSegment = [string]::Join('\', $parts[0..$i])
            if (-not $current.ContainsKey($part)) {
                $date = if ($fullPathSegment -eq $path.FullPath) { $path.Date } else { $null }
                $current[$part] = @{
                    'fullPath' = $fullPathSegment
                    'date' = $date
                    'children' = @{}
                }
            }
            $current = $current[$part]['children']
        }
    }
    return $tree
}

# ... (Previous code: parsing, BuildTree function, etc., remains unchanged)

# ... (Previous code: parsing, BuildTree function, etc., remains unchanged)

# Function to generate HTML for the folder tree with links and radio buttons
function GenerateHtml($tree, $baseUrl) {
    $html = "<ul>"
    foreach ($key in $tree.Keys) {
        $node = $tree[$key]
        $folderName = $key
        $date = if ($node['date']) { $node['date'] } else { "unknown" }
        $fullPath = $node['fullPath']
        # Convert file path to URL-safe path
        $pathParts = $fullPath -split '\\'
        $encodedParts = $pathParts | ForEach-Object { [System.Uri]::EscapeDataString($_) }
        $encodedPath = $encodedParts -join '/'
        $url = "$baseUrl$encodedPath"
        $childrenHtml = if ($node['children'].Count -gt 0) { GenerateHtml $node['children'] $baseUrl } else { "" }

        $html += "<li>"
        if ($node['date']) {
            $script:radioCounter++
            $name = "action_$script:radioCounter"
            $keepId = "keep_$script:radioCounter"
            $deleteId = "delete_$script:radioCounter"
            $archiveId = "archive_$script:radioCounter"
            $html += "<div class='folder' data-path='$fullPath'>"
            $html += "<details><summary><a href='$url' target='_blank'>$folderName</a> ($date)</summary>"
            $html += "<div class='radio-group'>"
            $html += "<label><input type='radio' name='$name' id='$keepId' value='keep' checked> Keep</label>"
            $html += "<label><input type='radio' name='$name' id='$deleteId' value='delete'> Delete</label>"
            $html += "<label><input type='radio' name='$name' id='$archiveId' value='archive'> Archive</label>"
            $html += "</div>"
            if ($node['children'].Count -gt 0) { $html += $childrenHtml }
            $html += "</details>"
            $html += "</div>"
        } else {
            $html += "<details><summary><a href='$url' target='_blank'>$folderName</a> ($date)</summary>"
            if ($node['children'].Count -gt 0) { $html += $childrenHtml }
            $html += "</details>"
        }
        $html += "</li>"
    }
    $html += "</ul>"
    return $html
}

# Generate an HTML file for each user with form submission to CouchDB
$script:radioCounter = 0
$baseUrl = "http://internal-server/folders/"  # Replace with your actual base URL
foreach ($group in $grouped) {
    $user = $group.Name
    $userPaths = $group.Group
    $tree = BuildTree $userPaths
    $treeHtml = GenerateHtml $tree $baseUrl

    # Sanitize username for filename
    $sanitizedUser = $user -replace '\\', '_'

$htmlHeader = @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <title>Folders for $user</title>
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f8f9fa; }
        h1 { color: #007bff; }
        ul { list-style-type: none; padding-left: 20px; }
        li { margin: 10px 0; }
        details summary { cursor: pointer; font-weight: bold; }
        .folder { padding: 10px; background-color: #fff; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .radio-group { margin-top: 5px; padding-left: 20px; }
        .radio-group label { margin-right: 15px; font-size: 0.9em; }
        .radio-group i { margin-right: 5px; }
        .btn-primary, .btn-secondary { margin: 10px 0 0 10px; }
        .sticky-header { position: sticky; top: 0; background-color: #f8f9fa; z-index: 1000; padding-bottom: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="sticky-header">
            <h1>Folders for User: $user</h1>
            <p class="text-muted">Review your folders below and select an action for each one. Submit your decisions when ready.</p>
            <p>Total folders: <span id="folderCount">$($userPaths.Count)</span> | Decisions made: <span id="decisionsMade">0</span></p>
            <div class="progress mb-3"><div class="progress-bar" id="progressBar" role="progressbar" style="width: 0%;" aria-valuenow="0" aria-valuemin="0" aria-valuemax="$($userPaths.Count)"></div></div>
            <button type="button" class="btn btn-secondary" id="expandAll">Expand All</button>
            <button type="button" class="btn btn-secondary" id="collapseAll">Collapse All</button>
            <input type="text" class="form-control mb-3" id="searchFolders" placeholder="Search folders...">
        </div>
        <form id="folderForm">
"@

$htmlFooter = @'
            <button type="submit" class="btn btn-primary">Submit Decisions</button>
        </form>
    </div>
    <script src="https://code.jquery.com/jquery-3.5.1.min.js"></script>
    <script>
        $(document).ready(function() {
            const totalFolders = parseInt($('#folderCount').text());
            function updateProgress() {
                const decisions = $('.folder input[type="radio"]:checked').length;
                $('#decisionsMade').text(decisions);
                const percent = (decisions / totalFolders) * 100;
                $('#progressBar').css('width', percent + '%').attr('aria-valuenow', decisions);
            }
            $('input[type="radio"]').change(updateProgress);
            updateProgress();

            $('#expandAll').click(function() {
                $('details').attr('open', true);
            });
            $('#collapseAll').click(function() {
                $('details').removeAttr('open');
            });
            $('#searchFolders').on('input', function() {
                const search = $(this).val().toLowerCase();
                $('.folder, li').each(function() {
                    const text = $(this).text().toLowerCase();
                    $(this).toggle(text.includes(search));
                });
            });
            $('#folderForm').submit(function(e) {
                e.preventDefault();
                const decisions = { keep: [], delete: [], archive: [] };
                $('.folder').each(function() {
                    const path = $(this).data('path');
                    const action = $(this).find('input[type="radio"]:checked').val();
                    if (action && decisions[action]) {
                        decisions[action].push(path);
                    }
                });
                $.ajax({
                    type: 'POST',
                    url: '/submit',
                    contentType: 'application/json',
                    data: JSON.stringify({ user: 
'@ + "'$user'" + @'
                    , decisions: decisions }),
                    success: function() {
                        alert('Decisions saved successfully!');
                    },
                    error: function() {
                        alert('An error occurred while saving decisions.');
                    }
                });
            });
        });
    </script>
</body>
</html>
'@

    $htmlContent = $htmlHeader + $treeHtml + $htmlFooter
    $htmlContent | Out-File "folders_$sanitizedUser.html" -Encoding UTF8
    Write-Host "Generated folders_$sanitizedUser.html"
}
