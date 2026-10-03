**Process For Updating Version for Clashboard**

* use apple configurator to download and extract the app files
* account > sign in, to authenticate, \~/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/ and the caches to intercept the download
* take the IPA to downloads, rename to .zip and extract to downloads
* right click, show package contents, grab the logic res > logic folder
* move that folder to downloads
* run the "process logic.sh" script from downloads in a new terminal
* this will convert the .csv files to human readable format, and move them to the "processed CSVs folder"
* compare to the current CSVs folder, and replace the same files for the new version
* run the python script to convert the CSVs 
* this will replace all of the existing json files, and append the existing json\_ maps
* a diff will be output to the terminal with all new and modified units, examine to make sure its correct
* update the names for the new troops, units, spells, buildings, etc in these maps
* find and download the assets for new content, add to the "assets" library in xcode, and make sure they go in the correct subfolder
* make sure equipment and crafted defense names (and rarity) are up to date as well
* update wall count, if applicable
* build and test for working assets, names, upgrade timers, etc
* update in-game changelog in the "what's new" section to reflect new version
* once satisfied, change build number and version number in xcode
* choose "any device arm64" as build target
* go to product > archive, and the publish build, this will take a minute. fix any errors if necessary
* on app store connect, update app details, add changelog, and publish build
* on the GitHub pages site, update the changelog to reflect new update additions









notes:

* make sure to import the decrypted CSV files and not the originals, those will not work
* place the previous CSVs in the previous folder to have a backup for the files incase something goes wrong  / needs compared
* make sure to be on the latest \*public\* release of xcode, otherwise the build will not be able to be pushed to the app store


