<?php
/* This file holds the templates class, which has functions for
storing, adjusting and outputting templates.

Version 1.01

Author(s): Daniel Paul
Last updated 18-06-06 by Daniel Paul */


class templates
{
	var $templateStore;
	
	
	// Constructor
	function templates()
	{
		
	}
	
	
	function createBlockReference ( $route, $includeLast = true, $subBlockMode = false )
	{
		// Takes route and returns a string to the storage area for its variables in templateStore
		if ( !is_array ( $route ) ) die ( "<b>templates->createBlockReference ( \$route )</b><br>$route is not an array!" );
		
		$blockref = '$this->templateStore';
		for ( $cbr = 0; $cbr < count ( $route ) -1; $cbr++ )
		{
			$blockref .= '[\'' . $route[$cbr] . '\']';
			if ( $route[$cbr] != '.' && !$subBlockMode ) $blockref .= '[$' . $route[$cbr] . '_i]';
			elseif ( $route[$cbr] != '.' && $subBlockMode ) $blockref .= '[' . ( count ( eval ( 'return ' . $blockref . ';' ) ) -1 ) . ']';
		}
		
		// Add last set of blocks, including the iteration block IF includeLast = true
		$blockref .= '[\'' . $route[$cbr] . '\']';
		if ( $includeLast ) $blockref .= '[\'$' . $route[$cbr] . '_i\']';
		return $blockref;
	}
	
	
	// Function for loading a new template into the template store
	function loadTemplate( $templateName, $extension = '.tpl', $variable = 'echo' )
	{
		// Check if the template file exists, if not spit out an error message
		if ( !file_exists ( 'templates/' . $templateName . $extension ) ) die ( "<b>templates->loadTemplate( \$templateName, [\$extension], [\$variable] )</b><br>Template <i>templates/$templateName$extension</i> could not be found!" );
		
		// If the template exists load it into the templateStore and replace ' with \'
		$template = str_replace ( "'", "\'", file_get_contents ( 'templates/' . $templateName . $extension ) );
		
		
		// Decide how to handle the output, either echo it (default) or throw it into
		// a variable ( usually used for nested templates )
		$outputMode = ( $variable == 'echo' ) ? 'echo' : $variable . ' .=';
		
		
		// Process variables with and without namespaces
		$varCount = preg_match_all ( '/\{(.*?)\}/i', $template, $matches, PREG_SET_ORDER );
		
		for ( $i =0; $i < $varCount; $i++ )
		{
			// Decide if this variable is root level or block level
			if ( strpos ( $matches[$i][1], '.' ) )
			{
				// Blockref variable
				$blockref = explode ( '.', $matches[$i][1] );
				// Slot the . block into pos 0 of the array
				$blockref = array_merge ( array ( '.' ), (array)$blockref );
				$blockref = $this->createBlockReference ( $blockref, false );
				
				$template = str_replace ( $matches[$i][0], '\' . ' . $blockref . ' . \'', $template );
			}
			else
			{
				// Root level variable
				$template = str_replace ( $matches[$i][0], '\' . $this->templateStore[\'.\'][\'' . $matches[$i][1] .'\'] . \'', $template );
			}
		}
		
		
		
		
		// Process any <if> <else> </if> blocks
		$template = preg_replace ( '/<if condition="?(!)?(\$.*?)(->.*?)?"?>(.*?)(<else>(.*?))?<\/if>/is', '\'; global \\2;' . "\n" . 'if ( \\1\\2\\3 ) { ' . $outputMode . ' \'\\4\'; }' . "\n" . 'else { ' . $outputMode . ' \'\\6\'; } ' . $outputMode . ' \'', $template );
		
		
		
		
		// Now split the template into individual lines
		$template = explode ( "\n", $template );
		
		// Process BEGIN and END blocks, and TEMPLATE placeholders
		// Use while loop instead of for loop so multiple items on one line are not missed
		$i =0; $route[0] = '.'; $nestLevel = 0;
		while ( $i < count ( $template ) )
		{
			// Look for BEGIN or END of blocks
			if ( preg_match ( '/<!-- (BEGIN|END) (.*?) -->/', $template[$i], $matches ) != 0 )
			{
				if ( $matches[1] == 'BEGIN' )
				{
					// Start of a block
					$nestLevel++;
					$route[$nestLevel] = $matches[2];
					
					// Generate block reference
					$blockref = $this->createBlockReference( $route, false );
					
					$replaceText = '\'; if ( is_array ( ' . $blockref . ' ) ) { for($' . $route[$nestLevel] . '_i =0; $' . $route[$nestLevel] . '_i < sizeof ( ' . $blockref . ' ); $' . $route[$nestLevel] . '_i++ ) { ' . $outputMode . ' \'';
					$template[$i] = str_replace ( $matches[0], $replaceText, $template[$i] );
				}
				
				else
				{
					unset ( $route[$nestLevel] );
					$nestLevel--;
					
					$replaceText = '\'; } } ' . $outputMode . ' \'';
					$template[$i] = str_replace ( $matches[0], $replaceText, $template[$i] );
				}
			}
			
			// Now look for and process TEMPLATE placeholders
			elseif ( preg_match ( '/<!-- TEMPLATE (.*?) -->/', $template[$i], $matches ) != 0 )
			{
				$template[$i] = str_replace ( $matches[0], str_replace ( "'", "\'", $this->getTemplate ( $matches[1] ) ), $template[$i] );
			}
			else
			{
				// If we have processed everything on this line, proceed to next
				$i++;
			}
		}
		
		// Check the template is not invalid ( EG more BEGIN's than END's )
		if ( $nestLevel !== 0 ) die ( "<b>templates->loadTemplate( \$templateName, [\$extension], [\$variable] )</b><br>Template <i>$templateName$extension</i> is invalid! Check you have closed all template blocks with a END statement." );
		
		return "$outputMode '" . implode ( "\n", $template ) . "';";
	}
	
	
	
	
	// Function for outputting a template
	function parseTemplate ( $templateName, $extension = '.tpl' )
	{
		// Load and then output the specified template
		$template = $this->loadTemplate ( $templateName, $extension );
		eval ( $template );
	}
	
	
	
	// Function for returning a template's output
	function getTemplate ( $templateName, $extension = '.tpl' )
	{
		// Load and then output the specified template
		$template = $this->loadTemplate ( $templateName, $extension, '$output' );
		eval ( $template );
		return $output;
	}
	
	
	
	
	// Function for putting variables into templateStore from an array. Each time
	// it is called an extra block is added, unless iteration is specified.
	function assignVars ( $array, $route = null, $iteration = -1 )
	{
		// Check we have got an array, and work out which iteration we are doing
		if ( !is_array ( $array ) ) die ( '<b>templates->assignBlockVars( \$array, [\$route], [\$iteration] )</b><br>Variable \$array is not an array!' );
		
		// Convert $route to a blockref if it is not null
		$blockref = ( $route == null ) ? null : explode ( '.', $route );
		// Slot the . block into pos 0 of the array
		$blockref = array_merge ( array ( '.' ), (array)$blockref );
		$blockref = $this->createBlockReference ( $blockref, false, true );
		
		if ( $iteration == -1 ) $iteration = ( is_array ( eval ( 'return ' . $blockref . ';' ) ) ) ? sizeOf ( eval ( 'return ' . $blockref . ';' ) ) : 0;
		
		// And finally chuck all our array values into our new iteration of this block
		foreach ( $array as $key => $value )
		{
			// Check if it is a root level variable
			if ( $route == null ) eval ( $blockref . '[' . $key . '] = \'' . str_replace ( "'", "\'", $value ) . '\';' );
			else eval ( $blockref . '[' . $iteration . '][' . $key . '] = \'' . str_replace ( "'", "\'", $value ) . '\';' );
		}
	}
}

?>