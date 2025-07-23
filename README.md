Personal WordPress development setup helper tool for [VVV Vagrant](https://varyingvagrantvagrants.org/) extending `config.yml` for it's configuration.

Depends on `yq`, `rsync`, `ssh` and expects WP-CLI to be available on remote WP instances. Additionally uses `lnav` for `bvv logs` command. Written and tested with Bash 5.1 on Linux.

Work in progress but implemented commands should mostly work. See issues section in bottom of this document.

Main repository for this project with issue tracker is at [Codeberg](https://codeberg.org/jasalt/bvv).

Windows is not supported for now.

# Docs

Functioning VVV setup (v3.15.1 or later) is expected, including VirtualBox (v7.1.6 or later) and Vagrant. Might work with other provider options also but not tested.

With configuration set in VVV `config.yml` and box provisioned, normal workflow for using the tool in plugin or theme development:

- `bvv up` starts VVV
- `bvv pull` pulls live application state to development environment
- `bvv logs` (in new terminal) shows logs during development
- *coding*
- `bvv push` deploys changes in git repositories to live server

## Extended VVV `config.yml` format

Custom configuration used by the tool is defined under `bvv` keyword in VVV [custom site template](https://github.com/Varying-Vagrant-Vagrants/custom-site-template/blob/master/README.md) located at `$VVV_ROOT/config/config.yml`.

The config format is not stable and may change, consider this when updating. Warnings for this can be found in commit messages.

```
hosts:
  ...
  site1:                           -- complete example with all features
    skip_provisioning: false
    description: "Demo Site 1 (production)"
    repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template.git
    php: 8.3
    hosts:
      - site1.test                      -- used for search-replacing the fqdns
    custom:
      wpconfig_constants:
        WP_DEBUG: true
        WP_DEBUG_LOG: true
        WP_DISABLE_FATAL_ERROR_HANDLER: true
      live_url: https://site1.fi        -- ignored (used by VVV)
    bvv:
      ssh_host: site1-server
      www_path: /home/master/site1/public_html
      fqdns: [example.com, www.example.com]   -- search-replaced with site's first hosts entry
      dump-path: /tmp       -- optional path to store temporary db dump, server home
      repositories:         -- excluded from pull command rsync
        plugins: [myplugin1, myplugin2] -- git repositories
        themes: [mytheme]
      wp-content-exclude: [debug.log, object-cache.php]  -- excluded from wp-content sync
      deactivate_plugins: [wp-ses, wp-sentry-integration]
      create_admin: true                            -- creates admin user "admin" "password"
      post_commands: [echo hello world]  -- executed in vagrant box afterwards
  site2:                           -- minimal example with pull functionality
    skip_provisioning: false
    description: "Demo Site 1 (production)"
    repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template.git
    php: 8.3
    hosts:
      - site2.test
    custom:
      wpconfig_constants:
        WP_DEBUG: true
        WP_DEBUG_LOG: true
        WP_DISABLE_FATAL_ERROR_HANDLER: true
      live_url: https://site2.fi
    bvv:
      ssh_host: site2-server
      www_path: /home/master/site2/public_html
      fqdn: site2.fi

```


## Commands
Most functionality expects that current working directory is within the VVV's `www` directory.

### `bvv up`
Starts VVV box with `vagrant up`, can be run from anywhere when environment variable or argument is given for `VVV_ROOT_PATH`.

### `bvv down` & `bvv halt`
Stop VVV box with `vagrant halt`, can be run from anywhere when environment variable or argument is given for `VVV_ROOT_PATH`.

### `bvv ssh` SSH to Vagrant box in the current folder
While editing plugin or theme files on host, sometimes it's necessary to run commands like `composer install` inside the Vagrant box.
Instead of issuing `vagrant ssh` and navigating to the mapped folder manually, `bvv ssh` does the navigation to the mapped directory automatically.

```
user@host ./my-plugin/ $ bvv ssh   # runs vagrant ssh and navigates to the mapped directory
vagrant@vagrant ./my-plugin/ $ composer install    # installs happily using composer inside Vagrant
```

Calculates relative path based on `cwd` mapped into `/srv/site-id/` in Vagrant box, `vagrant ssh` and `cd` into the relative path e.g. `vagrant ssh -c "cd /srv/site-id/ && bash -l"`.

When ran outside VVV directory on host it simply runs `vagrant ssh` in `VVV_ROOT_PATH`.

### `bvv pull [db|wp-content]` Pull live site state to development environment

Pulls remote server state (database and `wp-content`) to local environment with `bvv pull` similar way to [Wordmove](https://github.com/welaika/wordmove/) and other tools. Local changes in `wp-content` outside registered repositories are overridden and extra files not existing on remote are deleted. Database is also dropped re-initialized from remote dump.

The command is expected to be run from within `$VVV_ROOT/www/<site-id>/` so that the `site-id` can be parsed and the according pull config can be read from the `config.yml`.

Then site state is pulled from production roughly as in example script `pull.example.sh`.

Checks that required configuration is set and strips ending slashes from paths. Expects FS paths and fqdn should be in correct format.

Uses `rsync` and wp-cli over ssh. By default uses rsync to pull wp-content files, excluding configured  plugin and theme repositories and extra exclusions in `wp-content-exclude`, and then dumps and pulls remote database that is exported with wp-cli and gzipped, with `--delete-source-files` flag so the intermediate dump file is deleted from server.

Intermediate dump is by default saved in home folder by default to keep it out from public web directories and it's location can be changed with directive `dump_path` (not tested).

Usage examples:
- `bvv pull db` pulls only database, removing the dump file afterwards
- `bvv pull wp-content` pulls only wp-content files

Extra flags:
`--no-import` flag only downloads the database file, disables removing the dump file in development environment
`--no-delete` disables removing the dump file in development environment after the process

### `bvv push [--all]` deploys local git repository changes to site's remote WP instance

Pushing changes back to remote WP instance is accomplished with `git` and `bvv push` helper function pushes the current or all site's registered git repositories and pulls the changes on remote WP instance.

If remote WP instance cannot pull the changes, conflict resolution is left for user. Repository deploy key with read permission is also expected to be configured for both local environment and at the WP remote.

Items defined as repositories get excluded from `pull` command's `wp-content` rsync. They are also available for "pushing" or deploying repository changes to remote site.
```yaml
...
	  repositories:
	    plugins: [myplugin1, myplugin2]
		themes: [mytheme]
...
```

During invocation when `cwd` is in git repository that is defined in `config.yml`, pushes it's changes (to git remote) and pulls changes on remote WP instance by ssh'ing on it and cd'ing to the appropriate directory.

Otherwise when issued within `$VVV_ROOT/www/<site-id>/` (not within registered repository directory), or with `--all` flag, deploys all git repositories defined in `config.yml` (`repositories.themes[]` and `repositories.plugins[]`).

### `bvv logs [site-id]` opens all application logs with `lnav`

Lnav simplifies handling multiple log files at once but needs to be installed on remote. If it is missing, add it to `~/.local/bin/lnav`? For now, expect it to be installed.

VVV keeps site specific log files in `log` folder adjacent to `wp-content`, and `wp-content/debug.log`.

Usage examples:
- `bvv logs` opens all VVV log files for current application in `lnav` e.g. `lnav /home/user/vvv/www/mysite/public_html/wp-content/debug.log /home/user/vvv/www/mysite/log/`
  - expects `cwd` to be within `$VVV_ROOT/www/<site-id>/`
- `bvv logs site-id`
  - alternatively takes `site-id` as first positional argument so command can be run from anywhere and it's resolved from `config.yml`


## Customizing $VVV_ROOT

The tool should function without any environment variable setup and also allow setting the VVV path explicitly if needed.

On startup `$VVV_ROOT` is initialized pointing to a standard VVV root folder structure (having `Vagrantfile` and `./config/config.yml`) prioritizing methods:
1) `--vvv-root` command line argument
2) `VVV_ROOT_PATH` environment variable
3) dynamically identify current VVV root directory (having `Vagrantfile` and `./config/config.yml`) by traversing upwards in the directory tree

# Possible future features / draft ideas

## `bvv log` opens single log file with `less` (draft spec)

 Different log types for Nginx/Apache:
- Access
- Error
- Static

Additionally `wp-content/debug.log`.

### Yaml config `bvv.log_paths[]`:
Option A:
- access: /path/to/access.log
- error: /path/to/error.log
- static: /path/to/static.log
- debug: /path/to/wp-content/debug.log

Option B:
- log_paths=[/path/to/logs, /path/to/logs2]

### Usage examples (WIP)

bvv log [access|error|static|debug]
- expects to be run within vagrant
- defaults to opening curren local `wp-content/debug.log` with `less`

- Should it work from outside the VVV_ROOT? Probably should, but positional arg having two meanings would make things complicated e.g. `bvv log mysite` v.s. `bvv log access`

### Remote log reading (?)
Unclear if this tool should include external log viewing, while `config.yml` could contain a single "inventory" of such information.

bvv log [application-id] [?] [access|error|static|debug]
- How to choose production vs. local dev? `--remote` flag?

# Not implemented or considered for now

Hosts might include multiple domains (multi-site). This would require mapping each. For now, expect each site installation to simply use one domain.

Non-standard WP file structure not tested.

Only database and `wp-content` is are downloaded from live site. Other files such as WordPress Core files are not taken into account and need to be kept up to date manually. There could be a version check during sync that could warn if versions differ.

Expects VVV Vagrant to use VirtualBox provider (Ubuntu 24.04), might require modifications to work with Docker provider.

# TODO
- Check `~/vvv-local` as default location
- `bvv ssh [-p|prod|production]` ssh into production site, cd to www/relative path

# Issues

- Uses `set -x` for verbose debug output for now.
- `pull` broken outside plugin/theme repo but `bvv pull -all` works
- `pull` --no-import/--no-delete flags not implemented
- Windows is not supported. Rewrite with Rust clap & duct might help.

Issues can be raised on Codeberg issue tracker or by sending me a message.
