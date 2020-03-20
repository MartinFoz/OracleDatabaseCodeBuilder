# Introduction

Oracle Database Code Builder is a solution to the headache that is storing Database code (and in particular) Oracle code and objects.

Much searching on the internet yielded no results that didn't involve any sort of copying files manually to locations to enable install and backout scripts to run or to ensure original copies were updated so changes could be merged later on.

The idea behind this workaround to shoehorning database code into a repository is to automate the copying of files based on the installation and backout 
scripts that you create.  As a nice side effect to this copying, the PowerShell script checks your scripts to ensure that all the files are present ensuring that when they come to be executed, the files are at least found!

Included in the repo is an azure pipeline yaml build file that runs the PowerShell script and build a zip file containing your project code ready for execution against the database.  

# File Structure

The following file structure needs to be adhered to so that the process works without any issue

```
    RepoRoot
    |- schema
    |  |- <schemaName1>
    |  |  |- packages
    |  |  |- views
    |  |  |- etc...
    |  |- <schemaName2>
    |     |- packages
    |     |- views
    |     |- etc...
    |- scripts
    |  |- <project_1>
    |     |-backout
    |     |-install
    |- .gitignore
    |- azure-pipelines.yml
    |- PSPackageCreator.ps1
```

# Branch & Project Folder Names

For the script to locate the correct folder and scripts, the branch and folder names need to be similar.  The branching strategy that we use in our team means that we have 2 branches for a project / bug fix.  The naming convention we use and how the PowerShell script is configured to run is
```
{Project ref / bug ref}-{dev/development/master}
```
A `-master` branch is the master for the project and where pull requests are actions and releases created.  In the Azure Pipeline, the build only happens once the pull request has been complete.

A `-dev` or `-development` branch is the branch you push your changes to while developing.  If you have the git hook set up, the PowerShell script will run when you commit and cancel the commit if there are any errors

So the script can automatically find the project folder you are working on, it takes the branch name and removes any `-master`,`-dev` or `-development` suffixes and looks for a folder with that name in the `scripts` directory

If you don't want to build, add a NoLocalBuild.txt file to the root of your folder. The PowerShell script will pick this up and not check your install or backout scripts. This file is part of the .gitignore file list so won't be stored on the server so if you clone the project again, you will need to reinstate it.

# When you are developing

The main goal of this work-around is to ensure that the database object files that you are editing remain in the same place so that when it comes to `push` then `pull` into the `*-master` branch, there is no chance of a file being missed because it wasn't manually copied back to the schema location.

When you are changing or even adding a new database object, you will need to edit them in the schema location.  When the PowerShell script runs, it will copy the required file from the schema location to a folder it creates in your project folder called `objects`.

It knows that you need this file by analysing the path in your install script.  If it starts with `@objects/...` then it will look for the same path in the schema location.

So if it finds
```
@objects/data_schema/function/my_new_func.fnc
```
it will look in this location for the file
```
../schema/data_schema/function/
```
and copy it to the objects folder which it will create in the `install` folder for you and add to the `.gitignore`.  The contents of the `objects` folder are not stored as it is not required.  Old versions can be replicated if needed by rolling back to a particular commit point.

If you have any other files such as standing data updates, these can live in the root of the project folder or in a folder within the project folder.  It's up to you!

The PowerShell script also checks for the following when going through your install or backout scripts
1. Character Casing : SQL Plus is case sensitive so folder and file names need to match what is in the install script file.
2. That all files exists : if the `@` is not an `object` line it will still ensure that the file exists
3. That a backout exists : always need a backup plan!

 

# Enabling git commit hook

For those not in the know, a git hook is something that runs when an action is performed in git.  

To aid building the database files locally by running a PowerShell script, I created a git hook that will run after you execute the git commit command but before the actual commit takes place.

The hook checks for the presence of the `PSPackageCreator.ps1` file in the root of your repo.  If it isn't there then it will just carry on as normal.

Do the following commands in bash to enable the templates so each repo you create will have this feature  

1. this tells git that there are templates to use and where to find them

    ```git config --global init.templateDir '~/.git-templates'```
 

2. Create the directory to hold the global hooks

    ```mkdir -p ~/.git-templates/hooks```

  
3. put the contents of the hooks folder from the repo in the location you just created, probably `C:\Users\<userid>` folder on Windows 10. If you do `cd ~` in bash it will take you there.  If you do `echo ~`, it will show you the path
 

4. That's it. Any future repositories you create either manually using the init command or by cloning will contain that file and it will execute the command.

If you wanted to disable the pre-commit and move the check onto pre-push, then rename the `pre-commit` file to `pre-commit.sample`.  Copy the code from the pre-commit into `pre-push.sample` removing any existing code and the rename to `pre-push` 

(Instructions taken from https://coderwall.com/p/jp7d5q/create-a-global-git-commit-hook)

# Script Log table check
Part of our team's standards is to insert a record into a table when a script is run, install and backout.  There is a check that this exists and I had thought about taking it out but instead I have left it in as an example of adding in other checks into the code.


