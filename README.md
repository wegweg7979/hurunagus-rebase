# hurubase

[![CI](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml/badge.svg)](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml)

<img width="128" height="128" alt="Gemini_Generated_Image_rokat0rokat0roka" src="https://github.com/user-attachments/assets/89a83c6b-c4f1-4b26-ba06-a7ad6bc40cfb" />


A safe rebase helper for [hurunagus](https://github.com/wegweg7979) images and
other atomic Fedora/bootc distros.

You give it the address of the image you want to be running. It checks the
system you are on, works out what that target means for your machine, prints a
plan, and asks before it changes anything. Run the same command again after each
reboot — it completes whatever the previous boot left staged, and once you are
booted on the target it walks the post-rebase fixes, one prompt at a time.

```sh
git clone https://github.com/wegweg7979/hurunagus-rebase
cd hurunagus-rebase

./hurubase --check ghcr.io/wegweg7979/hurunagus-hyprland:latest   # plan only, changes nothing
sudo ./hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest      # preflight, plan, apply
# reboot
sudo ./hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest      # continue, or run the fix checklist
sudo ./hurubase --rollback                                        # back to the previous deployment
```


## What it never does

Deletes anything. Prunes a deployment. Edits `/etc/containers/policy.json` or
any other system file. Writes outside `$HOME` during the checklist. Reboots
without asking. Proceeds past a refusal.

