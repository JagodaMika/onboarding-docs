$rootDirectory = $pwd.ToString()
$errorsDirectory = $rootDirectory + '/logs/'
$errorsFile = $errorsDirectory + 'errors.txt'

# create directory for logs
New-Item -ItemType Directory -Force -Path $errorsDirectory | Out-Null

function writeToFile($message) { 
    Add-Content $errorsFile $message
}

function removeFile($fileName) {
    if (Test-Path $fileName) {
        Remove-Item $fileName
    }
}

function ifExists($path) {
    return Test-Path $path
}

$allFilesAbsolute = Get-ChildItem -recurse -Filter *.md | 
    ForEach-Object { $_.FullName }

$allFilesRelative = Get-ChildItem -recurse -Filter *.md | 
    Resolve-Path -Relative | 
    ForEach-Object { ('"/' + $_.Substring(2, $_.Length - 5) + '"').Replace('\', '/') };

function getPathTag($file) {
    $regex = '(?m)^path:\s?.*?$'
    $pathLine = Get-Content $file | Select-String -Pattern $regex
    $pathTag = ([string]$pathLine).Substring(6)

    $pathTag
}

function getNextPathTag($file) {
    $regex = '(?m)^next:\s?.*?$'
    $nexPathLine = Get-Content $file | Select-String -Pattern $regex
    $nextPathTag = ([string]$nexPathLine).Substring(6)

    $nextPathTag
}

function checkImageUrls($file) {
    $fileContent = Get-Content $file
    $parentContainer = Split-Path -Path $file

    foreach ($line in $fileContent) {
	    $r = [regex] "\(([^\[]*)\)"
		$match = $r.match($line)
		$url = $match.groups[1].value
		if ($url -like "*.png*") {
            $urlWithoutDots = $url -replace "\.(?=.*\.)", ""
            $fullDirectory = "$($parentContainer)$($urlWithoutDots)"
            if (-Not (Test-Path -Path $fullDirectory -PathType Leaf)) {
                writeToFile ('Missing image ' + $url + ' in ' + $file)
                writeToFile "`n"
            }
		}
    }
}

function getH1($file) {
    $regex = '(?m)^\# .'
    $content = Get-Content $file
    $match = $content -match $regex

    if($match.count -gt 0) {
            writeToFile ('File: ' + $file + ' contains H1 headings:')
            writeToFile ($match)
    }
}

function extractTags($file) {
    getPathTag $file
    getNextPathTag $file
}

function buildGraph() {
    $graph = @{ }

    foreach ($file in $allFilesAbsolute) {
        # Extract path and next path from markdown file metadata
        $tags = extractTags $file
        $pathTag = $tags[0]
        $nextPathTag = $tags[1]

        # Create a node
        $node = [PSCustomObject]@{
            File = $file
            Path = $pathTag
            Next = $nextPathTag
        };

        # Build graph
        $graph[$pathTag] = $node

        # Check the H1 headings since we have file reference here
        getH1 $file
        checkImageUrls $file
    }

    return $graph
}

function checkIfAllPathsPointsToValidFile($graph) {
    $graph.GetEnumerator() | ForEach-Object {
        if ($graph[$_.key].Path -notin $allFilesRelative) {
            writeToFile ('File: ' + $graph[$_.key].Path + ' does not exist at: ' + $graph[$_.key].File)
            writeToFile "`n"
        }
    }
}

function findEmptyNextTags($graph) {
    $emptyNextTags = @()
    $count = 0

    $graph.GetEnumerator() | ForEach-Object {
        if ($graph[$_.key].Next -eq '""') {
            $emptyNextTags += $graph[$_.key].File
            $count++
        }
    }

    if ($count -eq 0) {
        writeToFile 'There must be one and only one next tag set to ""'
        writeToFile "`n"
    }
    elseif ($count -gt 1) {
        writeToFile 'There should be one and only one next tag set to ""'
        writeToFile 'Found empty next tags at:'
        writeToFile $emptyNextTags
        writeToFile "`n"
    }
}

function checkIfAllNextsPointsToExistingPaths($graph) {
    $graph.GetEnumerator() | ForEach-Object {
        if (-Not ($graph.ContainsKey($graph[$_.key].Next))) {
            if ($graph[$_.key].Next -ne '""') {
                writeToFile ('File: ' + $graph[$_.key].Next + ' does not match any path tag at: ' + $graph[$_.key].File)
                writeToFile "`n"
            }
        }
    }
}

function checkSubtreeForCycles($graph, $startNode) {
    $visited = @()
    $hasCycle = $false
    $currentNode = $startNode
    $nextPath = $startNode.Next

    while ($nextPath) {
        if ($currentNode -in $visited) {
            $visited += $currentNode
            $hasCycle = $true;
            break;
        }
        else {
            $visited += $currentNode
        }

        $currentNode = $graph[$nextPath]
        $nextPath = $currentNode.Next
    }

    if ($hasCycle -eq $true) {
        writeToFile 'The following path leads to cycle:'
        writeToFile $visited.File
        writeToFile "`n"
    }
}

function checkGraphForCycles($graph) {
    $graph.GetEnumerator() | ForEach-Object {
        checkSubtreeForCycles $graph $graph[$_.key]
    }
}

function runFullTestFlow() {
    $graph = buildGraph

    # call all test methods here
    checkIfAllPathsPointsToValidFile $graph
    findEmptyNextTags $graph
    checkIfAllNextsPointsToExistingPaths $graph
    checkGraphForCycles $graph
}

function checkForErrors() {
    if (ifExists $errorsFile) {
        throw "Failed to process documents, see detailed information in errors.txt file"
    }
}

# run build test script
removeFile $errorsFile
runFullTestFlow
checkForErrors
