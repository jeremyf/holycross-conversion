# Blogger generates a massive XML file that doesn't have carriage returns.
# Apply those carriage returns for each entry so as not to overwhelm the
# parser

# Sequence
bundle exec ruby lib/process_assets.rb
