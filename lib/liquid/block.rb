module Liquid

  class Block < Tag
    IsTag             = /^#{TagStart}/o
    IsVariable        = /^#{VariableStart}/o
    FullToken         = /^#{TagStart}\s*(#{WordRegex}+)\s*(.*)?#{TagEnd}$/o
    ContentOfVariable = /^#{VariableStart}(.*)#{VariableEnd}$/o

    def parse(tokens)
      @nodelist ||= []
      @nodelist.clear

      while token = tokens.next_token!

        case token
        when IsTag
          if token =~ FullToken

            # if we found the proper block delimitor just end parsing here and let the outer block
            # proceed
            if block_delimiter == $1
              end_tag
              return
            end

            # fetch the tag from registered blocks
            if tag = Template.tags[$1]
              @nodelist << tag.new($1, $2, tokens)
            else
              # this tag is not registered with the system
              # pass it to the current block for special handling or error reporting
              unknown_tag($1, $2, tokens)
            end
          else
            message = "Tag '#{token}' was not properly terminated with regexp: #{TagEnd.inspect} "
            raise SyntaxError.new(message, tokens)
          end
        when IsVariable
          @nodelist << create_variable(token, tokens)
        when ''
          # pass
        else
          # token is a Liquid::Token. At this point we can just cast to string.
          @nodelist << token.to_s
        end
      end

      # Make sure that its ok to end parsing in the current block.
      # Effectively this method will throw and exception unless the current block is
      # of type Document
      assert_missing_delimitation!(tokens)
    end

    def end_tag
    end

    def unknown_tag(tag, params, tokens)
      case tag
      when 'else'
        message = "#{block_name} tag does not expect else tag", tokens.next_token
      when 'end'
        message = "'end' is not a valid delimiter for #{block_name} tags. use #{block_delimiter}"
      else
        message = "Unknown tag '#{tag}'" 
      end

      raise SyntaxError.new(message, tokens)
    end

    def block_delimiter
      "end#{block_name}"
    end

    def block_name
      @tag_name
    end

    ##
    # Not a fan of having to pass in both token and tokens here but it's
    # required to raise the SyntaxError.
    def create_variable(token, tokens)
      token.scan(ContentOfVariable) do |content|
        return Variable.new(content.first)
      end

      message = "Variable '#{token}' was not properly terminated with regexp: #{VariableEnd.inspect} "
      raise SyntaxError.new(message, tokens)
    end

    def render(context)
      render_all(@nodelist, context)
    end

    protected

    def assert_missing_delimitation!(tokens)
      raise SyntaxError.new("#{block_name} tag was never closed", tokens)
    end

    def render_all(list, context)
      output = []
      list.each do |token|
        # Break out if we have any unhanded interrupts.
        break if context.has_interrupt?

        begin
          # If we get an Interrupt that means the block must stop processing. An
          # Interrupt is any command that stops block execution such as {% break %} 
          # or {% continue %}
          if token.is_a? Continue or token.is_a? Break
            context.push_interrupt(token.interrupt)
            break
          end

          output << (token.respond_to?(:render) ? token.render(context) : token)
        rescue ::StandardError => e
          output << (context.handle_error(e))
        end
      end

      output.join
    end
  end
end
