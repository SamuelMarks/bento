Please refer to <https://github.com/chef-cookbooks/community_cookbook_documentation/blob/master/TESTING.MD>

## Testing Windows Server 2025

Windows Server 2025 requires a valid product key to build.
Please add the product key to your `.env` file at the root of the repository before building:

```
WINDOWS_SERVER_2025_STANDARD_EDITION=XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
```

You can then run the build normally:
```
bundle exec bin/bento build -o virtualbox-iso.vm os_pkrvars/windows/windows-2025-x86_64.pkrvars.hcl
```
