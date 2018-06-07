#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

# This file is derived from the 'Redmine converter from Textile to Markown'
# https://github.com/Ecodev/redmine_convert_textile_to_markown
#
# Original license:
# Copyright (c) 2016
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'open3'

module OpenProject::TextFormatting::Formatters
  module Markdown
    class TextileConverter
      TAG_CODE = 'pandoc-unescaped-single-backtick'.freeze
      TAG_FENCED_CODE_BLOCK = 'force-pandoc-to-ouput-fenced-code-block'.freeze
      DOCUMENT_BOUNDARY = "TextileConverterDocumentBoundary09339cab-f4f4-4739-85b0-d02ba1f342e6".freeze
      BLOCKQUOTE_START = "TextileConverterBlockquoteStart09339cab-f4f4-4739-85b0-d02ba1f342e6".freeze
      BLOCKQUOTE_END = "TextileConverterBlockquoteEnd09339cab-f4f4-4739-85b0-d02ba1f342e6".freeze

      def run!
        puts 'Starting conversion of Textile fields to CommonMark+GFM.'

        ActiveRecord::Base.transaction do
          converters.each(&:call)
        end

        puts "\n-- Completed --"
      end

      private

      def converters
        [
          method(:convert_settings),
          method(:convert_models),
          method(:convert_custom_field_longtext)
        ]
      end

      def convert_settings
        print 'Converting settings '
        Setting.welcome_text = convert_textile_to_markdown(Setting.welcome_text)
        print '.'

        Setting.registration_footer = Setting.registration_footer.dup.tap do |footer|
          footer.transform_values { |val| convert_textile_to_markdown(val) }
          print '.'
        end

        puts 'done'
      end

      ##
      # Converting model attributes as defined in +models_to_convert+.
      def convert_models
        models_to_convert.each do |the_class, attributes|
          print "#{the_class.name} "

          # Iterate in batches to avoid plucking too much
          batches_of_objects_to_convert(the_class, attributes) do |relation|
            orig_values = relation.pluck(:id, *attributes)

            old_values = orig_values.inject([]) do |old_values, values|
              old_values + values.drop(1)
            end

            joined_textile = concatenate_textile(old_values)

            markdown = convert_textile_to_markdown(joined_textile)

            markdowns_in_groups = []

            begin
              markdowns_in_groups = split_markdown(markdown).each_slice(attributes.length).to_a
            rescue
              # Don't do anything. Let the subsequent code try to handle it again
            end

            if markdowns_in_groups.length != orig_values.length
              # Error handling: Some textile seems to be misformed e.g. <pre>something</pre (without closing >).
              # In such cases, handle texts individually to avoid the error affecting other texts
              markdowns = old_values.map do |old_value|
                convert_textile_to_markdown(old_value)
              end

              markdowns_in_groups = markdowns.each_slice(attributes.length).to_a
            end

            new_values = []
            orig_values.each_with_index do |values, index|
              new_values << { id: values[0] }.merge(attributes.zip(markdowns_in_groups[index]).to_h)

              print '.'
            end

            next if new_values.empty?

            ActiveRecord::Base.connection.execute(batch_update_statement(the_class, attributes, new_values))
          end
          puts 'done'
        end
      end

      def convert_custom_field_longtext
        formattable_cfs = CustomField.where(field_format: 'text').pluck(:id)
        print "CustomField type text "
        CustomValue.where(custom_field_id: formattable_cfs).in_batches(of: 200) do |relation|
          relation.pluck(:id, :value).each do |cv_id, value|
            CustomValue.where(id: cv_id).update_all(value: convert_textile_to_markdown(value))
            print '.'
          end
        end

        puts 'done'
      end

      def convert_textile_to_markdown(textile)
        return '' unless textile.present?

        cleanup_before_pandoc(textile)

        # TODO pandoc recommends format 'gfm' but that isnt available in current LTS
        # markdown_github, which is deprecated, is however available.
        # --wrap=preserve will keep the wrapping the same
        # --atx-headers will lead to headers like `### Some header` and '## Another header'
        command = %w(pandoc --wrap=preserve --atx-headers -f textile -t markdown_github)
        markdown, stderr_str, status = begin
          Open3.capture3(*command, stdin_data: textile)
        rescue
          raise "Pandoc failed with unspecific error"
        end

        raise "Pandoc failed: #{stderr_str}" unless status.success?

        cleanup_after_pandoc(markdown)
      end

      def models_to_convert
        {
          ::Announcement => [:text],
          ::AttributeHelpText => [:help_text],
          ::Comment => [:comments],
          ::WikiContent => [:text],
          ::WorkPackage =>  [:description],
          ::Message => [:content],
          ::News => [:description],
          ::Board => [:description],
          ::Project => [:description],
          ::Journal => [:notes],
          ::Journal::MessageJournal => [:content],
          ::Journal::WikiContentJournal => [:text],
          ::Journal::WorkPackageJournal => [:description]
        }
      end

      def batches_of_objects_to_convert(klass, attributes)
        scopes = attributes.map { |attribute| klass.where.not(attribute => nil).where.not(attribute => '') }

        scope = scopes.shift
        scopes.each do |attribute_scope|
          scope = scope.or(attribute_scope)
        end

        # Iterate in batches to avoid plucking too much
        scope.in_batches(of: 50) do |relation|
          yield relation
        end
      end

      def batch_update_statement(klass, attributes, values)
        if OpenProject::Database.mysql?
          batch_update_statement_mysql(klass, attributes, values)
        else
          batch_update_statement_postgresql(klass, attributes, values)
        end
      end

      def batch_update_statement_postgresql(klass, attributes, values)
        table_name = klass.table_name
        sets = attributes.map { |a| "#{a} = new_values.#{a}" }.join(', ')
        new_values = values.map do |value_hash|
          text_values = value_hash.except(:id).map { |_, v| ActiveRecord::Base.connection.quote(v) }.join(', ')
          "(#{value_hash[:id]}, #{text_values})"
        end

        <<-SQL
          UPDATE #{table_name}
          SET
            #{sets}
          FROM (
            VALUES
             #{new_values.join(', ')}
          ) AS new_values (id, #{attributes.join(', ')})
          WHERE #{table_name}.id = new_values.id
        SQL
      end

      def batch_update_statement_mysql(klass, attributes, values)
        table_name = klass.table_name
        sets = attributes.map { |a| "#{table_name}.#{a} = new_values.#{a}" }.join(', ')
        new_values_union = values.map do |value_hash|
          text_values = value_hash.except(:id).map { |k, v| "#{ActiveRecord::Base.connection.quote(v)} AS #{k}" }.join(', ')
          "SELECT #{value_hash[:id]} AS id, #{text_values}"
        end.join(' UNION ')

        <<-SQL
          UPDATE #{table_name}, (#{new_values_union}) AS new_values
          SET
            #{sets}
          WHERE #{table_name}.id = new_values.id
        SQL
      end

      def concatenate_textile(textiles)
        textiles.join("\n\n#{DOCUMENT_BOUNDARY}\n\n")
      end

      def split_markdown(markdown)
        markdown.split(DOCUMENT_BOUNDARY).map(&:strip)
      end

      def cleanup_before_pandoc(textile)
        # Redmine support @ inside inline code marked with @ (such as "@git@github.com@"), but not pandoc.
        # So we inject a placeholder that will be replaced later on with a real backtick.
        textile.gsub!(/@([\S]+@[\S]+)@/, TAG_CODE + '\\1' + TAG_CODE)

        # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
        # See https://github.com/jgm/pandoc/issues/22
        textile.gsub!(/\|[\/\\]\d\. /, '| ')

        # Drop table alignment notation ("|>." or "|<." or "|=.") because pandoc does not support it
        # See https://github.com/jgm/pandoc/issues/22
        textile.gsub!(/\|[<>=]\. /, '| ')

        # Move the class from <code> to <pre> so pandoc can generate a code block with correct language
        textile.gsub!(/(<pre)(><code)( class="[^"]*")(>)/, '\\1\\3\\2\\4')

        # Remove the <code> directly inside <pre>, because pandoc would incorrectly preserve it
        textile.gsub!(/(<pre[^>]*>)<code>/, '\\1')
        textile.gsub!(/<\/code>(<\/pre>)/, '\\1')

        # Inject a class in all <pre> that do not have a blank line before them
        # This is to force pandoc to use fenced code block (```) otherwise it would
        # use indented code block and would very likely need to insert an empty HTML
        # comment "<!-- -->" (see http://pandoc.org/README.html#ending-a-list)
        # which are unfortunately not supported by Redmine (see http://www.redmine.org/issues/20497)
        textile.gsub!(/([^\n]<pre)(>)/, "\\1 class=\"#{TAG_FENCED_CODE_BLOCK}\"\\2")

        # Force <pre> to have a blank line before them
        # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
        textile.gsub!(/([^\n])(<pre)/, "\\1\n\n\\2")

        # Some malformed textile content make pandoc run extremely slow,
        # so we convert it to proper textile before hitting pandoc
        # see https://github.com/jgm/pandoc/issues/3020
        textile.gsub!(/-          # (\d+)/, "* \\1")

        # Remove empty paragraph blocks which trip up pandoc
        textile.gsub!(/\np\.\n/, '')

        # Replace numbered headings as they are not supported in commonmark/gfm
        textile.gsub!(/h(\d+)#./, 'h\\1.')

        # Add an additional newline before:
        # * every pre block prefixed by only one newline
        #   as indented code blocks do not interrupt a paragraph and also do not have precedence
        #   compared to a list which might also be indented.
        # * every table prefixed by only one newline (if the line before isn't a table already)
        # * every blockquote prefixed by one newline (if the line before isn't a blockquote)
        textile.gsub!(/(\n[^>|]+)\r?\n(\s*)(<pre>|\||>)/, "\\1\n\n\\2\\3")

        # Remove spaces before a table as that would lead to the table
        # not being identified
        textile.gsub!(/(^|\n)\s+(\|.+\|)\s*/, "\n\n\\2\n")

        # Wrap all blockquote blocks into boundaries as `>` is not valid blockquote syntax and would thus be
        # escaped
        textile.gsub!(/(([\n]>[^\n]*)+)/m) do
          "\n#{BLOCKQUOTE_START}\n" + $1.gsub(/([\n\A])> *([^\n]*)/, '\1\2') + "\n\n#{BLOCKQUOTE_END}\n"
        end
      end

      def cleanup_after_pandoc(markdown)
        # Remove the \ pandoc puts before * and > at begining of lines
        markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", "") }

        # Add a blank line before lists
        markdown.gsub!(/^([^*].*)\n\*/, "\\1\n\n*")

        # Remove the injected tag
        markdown.gsub!(' ' + TAG_FENCED_CODE_BLOCK, '')

        # Replace placeholder with real backtick
        markdown.gsub!(TAG_CODE, '`')

        # Un-escape Redmine link syntax to wiki pages
        markdown.gsub!('\[\[', '[[')
        markdown.gsub!('\]\]', ']]')

        # replace filtered out span with ins
        markdown.gsub!(/<span class="underline">(.+)<\/span>/, '<ins>\1</ins>')

        markdown.gsub!(/#{BLOCKQUOTE_START}\n(.+?)\n\n#{BLOCKQUOTE_END}/m) do
          $1.gsub(/([\n])([^\n]*)/, '\1> \2')
        end

        markdown
      end
    end
  end
end
