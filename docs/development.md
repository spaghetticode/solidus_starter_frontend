# Solidus Starter Frontend development information
This document aims to give some extra information for developers that are going 
to contribute to our `solidus_starter_frontend` component.

### Testing the extension
First bundle your dependencies, then run `bin/rake`. `bin/rake` will default to 
building the dummy app if it does not exist, then it will run specs. The dummy 
app can be regenerated by using `bin/rake extension:test_app`.

```shell
bin/rake
```

To run [Rubocop](https://github.com/bbatsov/rubocop) static code analysis run:
```shell
bundle exec rubocop
```

When testing your application's integration with this extension you may use its 
factories.
Simply add this require statement to your spec_helper:

```ruby
require 'solidus_starter_frontend/factories'
```

### Running the sandbox
To run this extension in a sandboxed Solidus application, you can run 
`bin/sandbox`. The path for the sandbox app is `./sandbox` and `bin/rails` will 
forward any Rails commands to `sandbox/bin/rails`.

Here's an example:

```
$ bin/rails server
=> Booting Puma
=> Rails 6.0.2.1 application starting in development
* Listening on tcp://127.0.0.1:3000
Use Ctrl-C to stop
```

Default username and password for admin are: `admin@example.com` and `test123`.

### Updating the changelog
Before and after releases the changelog should be updated to reflect the 
up-to-date status of the project:
```shell
bin/rake changelog
git add CHANGELOG.md
git commit -m "Update the changelog"
```

### Releasing new versions
Your new extension version can be released using `gem-release` like this:
```shell
bundle exec gem bump -v 1.6.0
bin/rake changelog
git commit -a --amend
git push
bundle exec gem release
```

## Solidus Compare tool
`solidus_compare` is a tool that we created to keep track of the changes made to
[solidus_frontend](https://github.com/solidusio/solidus/tree/master/frontend), 
which we used as source project in the beginning.

It is connected to our CI; when a new PR is opened, if a change is detected on 
Solidus Frontend, the workflow will fail and it will report the files changed.

In that case, it is needed to evaluate those changes and eventually apply them 
to our component. After this step, it is possible to mark those changes as 
"managed".

In practical terms:
- run locally `bin/solidus_compare` in any branch;
- evaluate the diff of the changes shown in the console;
- apply the required changes (if they are useful to the project);
- run `bin/solidus_compare -u` which will update the hashes in the config file;
- commit the changes and check the CI.

The tool internally works in this way:
- configuration file is loaded (`config/solidus_compare.yml`);
- remote GIT source is updated using the parameters provided by the config file;
- compare process is executed and a hash for each file is calculated;
- if they match the hashes saved in the configuration there are no differences.
