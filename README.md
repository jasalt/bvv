Personal WordPress development setup helper tool for VVV Vagrant.

Similar to [Wordmove](https://github.com/welaika/wordmove/) while more minimal in implementation and featureset.

Reuses default VVV `config.yml` file to store commands related to pulling production site state.

Uses rsync, ssh and expects WP-CLI to be installed on remotes, written on Bash (5.1.15).

# Program logic
## Initialization

Initialize `VVV_ROOT` pointing to a standard VVV root folder structure (having `Vagrantfile` and `./config/config.yml`) prioritizing methods:
1) `--vvv-root` command line argument
2) `VVV_ROOT` environment variable
3) search dir (having `Vagrantfile` and `./config/config.yml`) starting from cwd traversing to upper level directories up to filesystem root

## Config parsing
Uses `yq` to parse `./config/config.yml` for uses it's data for commands:

```
hosts:
  ...
  site1:                           -- complete example with all features
    skip_provisioning: false
    description: "Studio Laive site (sync from production)"
    repo: https://github.com/Varying-Vagrant-Vagrants/custom-site-template.git
    php: 8.3
    hosts:
      - site1.test                      -- used for search-replacing the fqdn
    custom:
      wpconfig_constants:
        WP_DEBUG: true
        WP_DEBUG_LOG: true
        WP_DISABLE_FATAL_ERROR_HANDLER: true
      live_url: https://site1.fi        -- ignored (used by VVV)
    bvv:
      ssh_host: site1-server
      www_path: /home/master/site1/public_html
      fqdn: example.com     -- get's search-replaced with site[hosts][0]
	  dump-path: /tmp       -- optional path to store temporary db dump, server home
	  wp-content-exclude:
	    plugins: [myplugin1, myplugin2] -- optional, one or many
		themes: [mytheme]               -- optional, one or many
		other: [object-cache.php]       -- optional, one or many
	  post-commands:
	    deactivate_plugins = [myplugin3, myplugin4]
	    create_admin = true                            -- creates admin user "admin" "password"
	    extra_commands = [wp cache flush, echo hello]  -- executed in vagrant box afterwards

  site2:                           -- minimal example with for pull command
    skip_provisioning: false
    description: "Studio Laive site (sync from production)"
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

Commands are ran based on the parsed data.

### `bvv ssh` SSH to Vagrant box in the current folder
Calculate relative path based on `cwd` mapped into `/srv/site-id/` in Vagrant box, `vagrant ssh` and `cd` into the relative path e.g. `vagrant ssh -c "cd /srv/site-id/ && bash -l"`.

Simply `vagrant ssh` if ran outside VVV directory on host.

### `bvv up`
Starts VVV box with `vagrant up`, can be run from anywhere when environment variable or argument is given for `VVV_ROOT`.

### `bvv pull` Pull live site state to development environment

The command is expected to be run from within `$VVV_ROOT/www/<site-id>/` so that the `site-id` can be parsed and the according pull config can be read from the `config.yml`.

Then site state is pulled from production roughly as in example script `pull.example.sh`.

Validation should be done for having all required data before running command. FS paths and fqdn should be in correct format.

Uses rsync and wp-cli over ssh. Example procedure is in `pull.example.sh`. By default uses rsync to pull wp-content files, with optional exclusions listed in config, and then pulls database that is exported with wp-cli and gzipped, with --delete-source-files flag so the original file is deleted on server.

#### `bvv pull db` pulls only database, removing the dump file afterwards

`--no-import` flag only downloads the database file, disables removing the dump file
`--no-delete` disables removing the dump file

#### `bvv pull wp-content` pulls only wp-content files

# Possible future features
Not implemented for now.

## Log commands
### `bvv logs` (draft spec)
Shortcut to open `less` or `lnav` for different logs across applications.

Different log types for Nginx/Apache:
- Access
- Error
- Static

Additionally `wp-content/debug.log`.

Lnav could simplify handling multiple log files but needs to be installed on remote. If it is missing, add it to `~/.local/bin/lnav`?

#### Yaml config directive `bvv.log_paths[]`


#### Usage examples (WIP)

bvv log [access|error|static|debug]
- expects to be run within vagrant
- defaults to opening curren local `wp-content/debug.log` with `less`

- Should it work from outside the VVV_ROOT? Probably should, but positional arg having two meanings would make things complicated e.g. `bvv log mysite` v.s. `bvv log access`

##### Remote log reading (?)
Unclear if this tool should include external log viewing, while `config.yml` could contain a single "inventory" of such information.

bvv log [application-id] [?] [access|error|static|debug]
- How to choose production vs. local dev? `--remote` flag?

###### Yaml config:
Option A:
- access: /path/to/access.log
- error: /path/to/error.log
- static: /path/to/static.log
- debug: /path/to/wp-content/debug.log

Option B:
- log_paths=[/path/to/logs, /path/to/logs2]

# Not implemented or considered for now

Hosts might include multiple domains (multi-site). This would require mapping each. For now, expect each site installation to simply use one domain.

Non-standard WP file structure not tested.

Only database and `wp-content` is are downloaded from live site. Other files such as WordPress Core files are not taken into account and need to be kept up to date manually. There could be a version check during sync that could warn if versions differ.

Expects VVV Vagrant to use VirtualBox provider (Ubuntu 24.04), might require modifications to work with Docker provider.
