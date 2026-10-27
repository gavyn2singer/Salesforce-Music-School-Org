# Publish steps

1. The dashboard is already on Tableau Public, and the link is in tableau/README.md. Open it once in a private browser window to check that it loads without signing in.

2. Add the tableau folder to GitHub. Pick one option.

   Option A: web upload
   1. Open https://github.com/gavyn2singer/Salesforce-Music-School-Org.
   2. Click Add file, then Upload files.
   3. Drag the tableau folder from the github_package folder into the box.
   4. Drag the updated README.md too, so it replaces the old one.
   5. Commit to the main branch.

   Option B: git
   ```
   git clone https://github.com/gavyn2singer/Salesforce-Music-School-Org.git
   cp -r path/to/github_package/tableau Salesforce-Music-School-Org/
   cp path/to/github_package/README.md Salesforce-Music-School-Org/README.md
   cd Salesforce-Music-School-Org
   git add tableau README.md
   git commit -m "Add Tableau dashboard folder"
   git push
   ```
