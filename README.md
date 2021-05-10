# HashCopy
My PowerShell alternative to the Nuix Evidence Mover tool

Please note this was written in PowerShell v7 - I don't think it will work with whatever comes standard with Windows 10 (v3? 5?).
You can get PowerShell v7 right here on github - https://github.com/PowerShell/PowerShell

I wrote this as I was not a fan of the Nuix Evidence Mover (NEM) tool for a few reasons:

1. Order of operation - NEM copes the file, then hashes the source and then destination file and runs the comparison. I wanted a tool that would hash the source file, then     copy it, then hash the destination file.
2. Logging implementation - NEM puts the log files in the root destination directory. I want the log files in a centralised location as I will be using the script on multiple PCs - I don't yet have the network setup so this is yet to be implemented in the code - it just writes to c:\temp at the moment.
3. Speed - I compared performance between my script and NEM on a PC with NVMe drives and NEM was much slower - it's possibly because I believe NEM is also hashing the file as it is copying it.

HashCopy is currently inferior to NEM in a few ways, which I am planning on continuing to address.

1. NEM will check if the source file already exists in the destination directory and if so will just hash it and only copy it if it doesn't match.
2. NEM has a checkbox to turn recursively copying subdirectories on and off.

I would classify myself as beginner to intermediate skill level with PowerShell; there will surely be many things in this script that can be improved.
A lot of my previous scripts had no error handling at all, it's something I have really only stated thinking about with my last few tools.
I still feel like this script makes too many assumptions that things have gone right.

The GIF is an adaptation of a still image I found on www.poeticoding.com and is used with permission - please go check out the website!

I have no idea what the community is like here on GitHub, will anyone ever read this?
