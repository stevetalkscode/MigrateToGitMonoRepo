##########################################################################################################################################################
#
# This script is an example of how to create a single 'mono-repo' by merging in other Git repositories
# Written by @stevetalkscode
# MIT Licence applies
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# 
# TL;DR - Run at your own risk, and don't blame me if something blows up. 
#
##########################################################################################################################################################

##########################################################################################################################################################
#
# Stage 1 - Prepare variables
#
# This section is based on destroying the target folder if it already exists, so use with care
#
# (Set up the variables for path to the target folder, including changing the current drive to the root of the target)
#
##########################################################################################################################################################

$GitTargetRoot = "C:\DemoOfMergeRepo"                  #Change this as appropriate
$GitTargetFolder = "TargetRepository"                  #Change this as appropriate
$GitArchiveFolder = "ArchivedBranches"                 #Change this as appropriate
$GitArchiveTags  = "ArchivedTags"                      #Change this as appropriate

# Set up variables for Git properties

$GitUserName = "Migration Automation Script"           #Change this as appropriate
$GitEMail = "my.email@mydomain.tld"                    #Change this as appropriate

# Set up variable with default URL to repo if all repos are in same provider e.g. GitHub, AzureDevOps

$originRoot = "https://github.com/stevetalkscode/"     #Change this as appropriate and ensure this ends with forward-slash!

# Set up variable for branch that holds the name of the branch to merge specified mergeBranch into
# I have set to '__RepoMigration' to avoid conflict with common branch names in existing repos.
# This can alway be renamed before pushing to the new target origin

$newMergeTarget = "__RepoMigration"                    #Change this as appropriate 

# To avoid folder or branch name clashes, set a prefix that should not be present in the source repos

$TempFolderPrefix = "____#####____";                   #Change this as appropriate

# Create an array of objects that describe what to migrate
# Each item will have the following attributes
#
# originRoot - if the repo is in another orgin root, adding the URL here will override the default set in the global $originRoot variable above
# repo- The name of the repo to be merged into the new repo
# folder - giving a name to the sub-folder in the target branch - though note, this is not set until the end when all repos have been merged.
# sub-directory - if folder is a root to many merged repos, this will be the target folder for the actual code
# mergeBranch - only one branch from the source will be merged into the single target branch in the new repo 
# tempFolder - setting a temporary folder name that won't clash with folder names that may be in other 

$items = (    

    [pscustomobject]@{ originRoot="";repo="Dummy1"; folder="From_Dummy_1"; subDirectory="";         mergeBranch="develop"; tempFolder="##Repo1" },

    [pscustomobject]@{ originRoot="";repo="Dummy2"; folder="From_Dummy_2"; subDirectory="";         mergeBranch="main";    tempFolder="##Repo2" },

    [pscustomobject]@{ originRoot="";repo="Dummy3"; folder="From_Dummy_3"; subDirectory="";         mergeBranch=""; tempFolder="##Repo3" },

    [pscustomobject]@{ originRoot="https://github.com/microsoft/";repo="MS-DOS"; folder="Microsoft"; subDirectory="MS_DOS"; mergeBranch="master"; tempFolder="##MS_DOS" }
)

cls

# Create a list to capture all the temporary folders that need to be renamed at the end (and exlcuded from directory listings when switching branches)

$TargetsToRename = New-Object -TypeName "System.Collections.ArrayList";
$GitTargetPath  = $GitTargetRoot + "\" + $GitTargetFolder

##########################################################################################################################################################
#
# Stage 2 - Prepare the file system
#
# Filesytem preamble - this section handkes trashing and recreating the file system folder strucure for the target repository
#
##########################################################################################################################################################


$FolderExists = Test-Path $GitTargetRoot

If ($FolderExists -eq $False) {
    MD $GitTargetRoot 
}

$FolderExists = Test-Path $GitTargetPath

If ($FolderExists -eq $True) {
    cd $GitTargetPath  
    Get-ChildItem -Force -Recurse | Where-Object{($_.Attributes.ToString().Split(“, “) -contains “Hidden”)}| foreach {$_.Attributes = “Archive”}
    Remove-Item ".git" -Force -Recurse ;
    cd ..
    Remove-Item -Recurse -Force $GitTargetPath -ErrorAction Stop;
}

MD $GitTargetPath
$Acl = Get-Acl $GitTargetPath
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($Ar)
Set-Acl $GitTargetPath $Acl

Set-Location -Path $GitTargetPath

cls

##########################################################################################################################################################
#
# Stage 3 - Initialise the new repostitory
#
# Filesytem preamble - this section handkes trashing and recreating the file system folder strucure for the target repository
#
##########################################################################################################################################################

CD $GitTargetPath
cls
git init -b $newMergeTarget
git config --system core.longpaths true
git config user.name $GitUserName
git config user.email $GitEMail
cat .git/config

echo Hello > Temporary_File_For_Initial_Commit.ThisIsNotARealFile
git add .
git commit -m "Add temporary file for to enable merging of repositories to be initialised" 
git rm Temporary_File_For_Initial_Commit.ThisIsNotARealFile
git commit -m "Remove temporary file before merge commences" 


##########################################################################################################################################################
#
# Stage 4 - The migration loop
#
# This is the guts of the script that loops over the array of source repositories and does the following
#
# * pulls the source repository
# * gets a list of all branches from the origin
# * rebranches it to an archive branch 
# * goes back to the target branch
# * merge (if specified) a branch into the target branch (at this point, we have to be careful about common folder names and hence why we then ...)
# * move the contents of the branch into a sub-folder that has a temporary name that (we hope) does not clash with any other temp/source folder names
# * migrate all existing tags to a nested tag name strucutre rooted at the value in $GitArchiveTags
#
##########################################################################################################################################################

foreach( $obj in $items)
{
    $branchName = $obj.folder.Replace('\','/');
    $currentFolder = $obj.folder;
    $currentRepo = $obj.repo;    
    $writefolder = $obj.subDirectory + '\' + $obj.folder;
    $mergeBranch = $obj.mergeBranch;
    $tempFolder = $TempFolderPrefix + $obj.tempFolder;
    $TargetsToRename.Add($tempFolder);
    $remoteOrigin = $obj.originRoot;

    if ($remoteOrigin -eq ""){
        $remoteOrigin = $originRoot;
    }    

    git remote add origin "$remoteOrigin/$currentRepo"
    git pull  --all --allow-unrelated-histories -v
    git branch -r | Select-String -Pattern "->" -NotMatch | Select-String -pattern "^  origin/" | foreach { $_ -replace '^  origin/', '' } | Foreach { 
    git checkout  -b $_ origin/$_ --no-track
    git branch -m $GitArchiveFolder/$branchName/$_ }
    git checkout -f
    git checkout $newMergeTarget
    git remote remove origin
    
    If ($mergeBranch -ne "")
    {
        git merge $GitArchiveFolder/$currentFolder/$mergeBranch --allow-unrelated-histories 
        mkdir $tempFolder
        $source="*" #path to files
        dir -exclude $TargetsToRename | %{git mv $_.Name $tempFolder.Replace('\','/')}
        git commit -m "Migration of $currentRepo Repo to \$tempFolder sub-directory completed. Folder rename of $tempFolder to $writefolder to be completed once all repositories merged." 
    }

    git tag | Select-String -Pattern "^$GitArchiveTags/" -NotMatch | Foreach { 
        git tag $GitArchiveTags/$currentFolder/$_  $_
        git tag -d $_
    }
}


##########################################################################################################################################################
#
# Stage 5 - Rename the temporary folders
#
# At this point, the migration is technically complete except for some housekeeping.
#
# Using the arrary of sources, rename the temporary folder in the target branch to the intended folder name
#
##########################################################################################################################################################

foreach( $obj in $items){
    $tempFolder = $TempFolderPrefix + $obj.tempFolder;

    $FileExists = Test-Path $tempFolder
    If ($FileExists -eq $True) {   
        If($obj.subDirectory -ne ""){
            $SubFolderExists = Test-Path $obj.subDirectory        
            If ($SubFolderExists -eq $False) {
                md $obj.subDirectory
            }
        }

        $writefolder = "";

        If($obj.subDirectory -ne "") {
         $writefolder = $writefolder + $obj.subDirectory + '\'
         }

        $writefolder =  $writefolder+ $obj.folder;
        %{git mv $tempFolder $writefolder}
        git add -u $writefolder
        git commit -m "Rename temporary folder $tempFolder to correct folder $writefolder"
    }
}


##########################################################################################################################################################
#
# Stage 6 - At this point we have a complete local repostory of the migrated sources as a single repository
#
# How you proceed from here is up to you, but further steps are likely to include
#
# Pushing up to a cloud host 'as-is' or more likely creating a new repo in your cloud destination (GitHub, AzureDevOps, BitBucket et al) and doing 
# some or all of the following
#
# (a) Add the cloud repo as a new origin
#
#     git remote add origin "your_url"
#
# (b) Pull the remote, but using the unrelated histories feature
#
#     git pull  --all --allow-unrelated-histories -v
#
# (c) Checkout the main branch - depending on when/how you created the cloud desination, the branch will likely be called main or master.
#
#     Given the new standards adopted, if called master, rename the branch as Main going forward
#
#     git checkout  -b Main origin/master 
#
# (d) Checkout the target branch you created from migration
#
#     git checkout $newMergeTarget 
#
# (e) Merge the Main branch you have created out from cloud into the checked out target branchbranch
#
#     git merge Main --allow-unrelated-histories 
#
# (f) Delete the Main branch and rename your target branch to Main
# 
#     git branch -d Main
#     git branch -m Main     
#
# (g) Depending on your standard, you may want to branch again into a 'Develop' branch
#
#     git checkout -b Develop
#
# (h) Push the Main and Develop branches to the origin
#
#     git -c diff.mnemonicprefix=false -c core.quotepath=false --no-optional-locks push -v -u origin Main
#     git -c diff.mnemonicprefix=false -c core.quotepath=false --no-optional-locks push -v -u origin Build
#
#
# (i) Lastly, loop through all the archive branches and push these up to origin as well.
#
#     git branch | Select-String -pattern "^  $GitArchiveFolder/" | foreach { $_ -replace '^\*', ' ' } | foreach { $_ -replace '^  ', '' } | foreach { 
#     git -c diff.mnemonicprefix=false -c core.quotepath=false --no-optional-locks push -u origin $_ }
#
##########################################################################################################################################################

