# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#    http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Jekyll

  # This generator will find all the files in the
  # directory where all the markdown is stored
  # and create the site.data["translations"] map
  # which is used to track translations of a Page
  #
  # Define the source of the markdown by Setting
  # 'WFContentSource' in the config.yaml


  # Extract language code to name mappings.
  class LanguageNameGenerator < Generator
    priority :highest
    def generate(site)
      @contentSource = site.config['WFContentSource']
      if @contentSource.nil?
        Jekyll.logger.info "WFContentSource is not defined - no " +
          "translations to map"
        return
      end

      @acceptedExtensions = [".markdown", ".md", ".html"]

      # Load contributors
      # Because this generator is highest priority,
      # set a global variables here
      data = YAML.load_file(site.config['WFContributors'])
      site.data["contributors"] = data


      contributorsFilepath = File.join(site.config['WFContributors'])
      contributesData = YAML.load_file(contributorsFilepath)
      site.data["contributors"] = contributesData

      # Get the contents of _langnames.yaml
      langNamesData = YAML.load_file(site.config['WFLangNames'])

      # Make the language code and matching language name available
      # to all of the site
      site.data["language_names"] = langNamesData
      site.data["primes"] = translations(site)
    end

    # Generate translations manifest.
    def translations(site)
      # Check if langs_available key is defined, if not return no translations
      if not site.config.key? 'langs_available'
        return {}
      end

      primaryLanguage = site.config['primary_lang'] || 'en'
      primaryLangFilepath = [@contentSource, primaryLanguage, ''].join '/'
      primaryLangFilePattern = File.join primaryLangFilepath, '**', '*.*'

      # Get files in directory
      fileEntries = Dir.entries( primaryLangFilepath )
      site.data['primes'] = {}
      allPages = []
      pagesTree = {"id" => "root", "pages" => [], "subdirectories" => {}}

      handleFileEntries(allPages, pagesTree, site, primaryLangFilepath, '.', fileEntries)

      allPages
      # This maps all the files in the primary language directory
      # to any of the available translations files
      #Dir.glob(primaryLangFilePattern).inject({}) { |result, fullFilepath|
      #  # Get the relative directory the file lives in (i.e. where in a
      #  # language it would live)
      #  relativeDirectory = File.dirname fullFilepath.sub(primaryLangFilepath, '')
      #
      #  # skip underscore directories, _code and _assets
      #  next result if relativeDirectory =~ /^_/
      #  next result if relativeDirectory =~ /\/_(code|assets)/
      #
      #  # Get just the filename of the file
      #  filename = File.basename fullFilepath
      #  # Get the relative directory and filename for the file
      #  relativePath = File.join relativeDirectory, filename
      #
      #  # This method looks for the equivalent translation file for a file
      #  # by looping over the langs_available array from config
      #  result[relativePath] = site.config['langs_available'].select { |hl|
      #    File.exists? File.join(contentSource, hl, relativeDirectory, filename)
      #  }
      #
      #  langPage = create_page(
      #    site,
      #    relativeDirectory,
      #    filename,
      #    primaryLanguage,
      #    false)

      #  result
      #}
    end

    def handleFileEntries(allPages, pagesTrees, site, rootPath, relativePath, fileEntries)
      fileEntries.each { |fileEntry|
        if File.directory?(File.join(rootPath, relativePath, fileEntry))
          if fileEntry =~ /^_/
            next
          end
          if fileEntry =~ /\/_(code|assets)/
            next
          end
          if fileEntry == "." || fileEntry == ".."
            next
          end
          pagesTrees['subdirectories'][fileEntry] = {
            "id" => fileEntry,
            "pages" => [],
            "subdirectories" => {}
          }

          if relativePath == '.'
            nextRelativePath = fileEntry
          else
            nextRelativePath= File.join(relativePath, fileEntry)
          end
          handleFileEntries(
            allPages,
            pagesTrees['subdirectories'][fileEntry],
            site,
            rootPath,
            nextRelativePath,
            Dir.entries( File.join(rootPath, nextRelativePath) )
            )
        else
          if @acceptedExtensions.include? File.extname(fileEntry)
            page = create_page(
                site,
                relativePath,
                fileEntry,
                'en',
                false)

            if site.data['primes'].key?(page.url)
              raise "Two pages at the same URL #{page.url}"
            end
            page.data['pages'] = pagesTrees
            supportedTranslations = site.config['langs_available'].select { |languageId|
              if languageId == site.config['primary_lang']
                return false
              end
              File.exists? File.join(@contentSource, languageId, relativePath, fileEntry)
            }

            page.data['is_localized'] = supportedTranslations.count > 0
            translated_pages = []
            supportedTranslations.each do |languageId|
              translationFilePath = File.join @contentSource, languageId, relativePath

              page = create_page(
                site,
                relativePath,
                fileEntry,
                languageId,
                true)
              page.data.merge!('is_localized' => true, 'is_localization' => true)
              translated_pages << page
            end
            page.data["translations"] = translated_pages

            if page.name.start_with? ('index')
              pagesTrees['index'] = page
            else
              pagesTrees['pages'] << page
            end

            allPages << page
            site.pages << page
          end
        end
      }
    end

    # Creates a new LanguagePage or a LanguageAsset, and adds it to site.pages
    # unless process is false.
    # Returns only LanguagePage instance, otherwise nil.
    def create_page(site, relative_dir, file_name, langcode, process = true)
      # Don't process underscore files.
      if relative_dir =~ /^_/
        return nil
      end

      case file_name
      when /\.(markdown|md|html)|sitemap\.xml|feed\.xml/
        directories = relative_dir.split(File::SEPARATOR)
        rootFolderName = directories[0]

        page = nil
        case rootFolderName
        when 'updates'
          page = UpdatePage.new(site, relative_dir, file_name, langcode)
        when 'fundamentals'
          puts "Creating Fundamentals: " + file_name
          puts "Path: " + relative_dir
          page = FundamentalsPage.new(site, relative_dir, file_name, langcode)
        when 'styleguide', 'shows'
          page = LanguagePage.new(site, relative_dir, file_name, langcode)
        when '.'
          page = LanguagePage.new(site, relative_dir, file_name, langcode)
        else
          Jekyll.logger.info "Unsure what Page to use for markdown files in the \"" +
            rootFolderName + "\" directory."
          raise Exception.new("main-generator.rb: Unsure what Page to use for markdown files in the \"" +
            rootFolderName + "\" directory.")
        end

        if process

        end
        page
      when /\.(png|jpg|gif|css|mp4|webm|vtt|svg)/
        # Copy across other assets.
        asset = LanguageAsset.new(site, relative_dir, file_name, langcode)
        site.static_files << asset if process
        nil
      end
    end
  end

end
