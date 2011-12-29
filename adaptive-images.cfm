<cfscript>
	/*
	*	Some simple directions
	*		- by default this relies on the cookie set in the client in regards to the decive resolution
	*		- you can request an original by calling the file with ?original=1
	*		- you can now request specific dimensions by adding the values to the URL 
	*			ie: ?width=100 						: resizes image to a width of 100
	*				?height=100 					: resizes image to a height of 100
	*				?width=100&height=100			: scales an image to fit into 100x100
	*				?width=100&height=100&crop=1	: scales an image and then crops to the specified dimensions
	*		If a file does not exists you can choose to return an image or 404
	*		If an error occurs an empty image stating image could not be created is generated
	*/
	writeLogs		= false; 				// whether or not to log activity
	log_file		= "adaptive-images";	// name of logfile
	resolutions 	= [1382,992,768,430]; 	// the resolution break-points to use (screen widths, in pixels)
	cache_path		= "ai-cache"; 			// where to store the generated re-sized images. This folder must be writable.
	jpg_quality 	= 80; 					// the quality of any generated JPGs on a scale of 0 to 100
	sharpen     	= true; 				// Shrinking images can blur details, perform a sharpen on re-scaled images?
	watch_cache 	= true; 				// check that the responsive image isn't stale (ensures updated source images are re-cached)
	browser_cache 	= 60*60*24*7; 			// How long the BROWSER cache should last (seconds, minutes, hours, days. 7days by default)
	mobile_first	= true; 				// If there's no cookie deliver the mobile version (if FALSE, delivers original resource)
	scale_by		= "width";				// this is overwritten if a height only value is passed or if width and height is passed we can choose scale (default) or crop (by passing url var crop)
	interpolation	= "blackman";			// interpolation algorithm to use when scaling/resizing file
	
	// make sure the supplied break-points are in ascending size order
	// uncomment if you don;t tend to put your resolutions in order above
	// arraySort(resolutions, "numeric","desc");
	
	resolution 		= resolutions[1]; 			// default resolution 
	res_directory	= resolution;				// default namne of directory to save file in
	
	// document root and file definition
	document_root  	= expandPath("/");
	
	// set requested uri based on server
	if (structKeyExists(cgi,"HTTP_X_REWRITE_URL"))		// IIS IIRF (Ionics Isapi Rewrite Filter)
		requested_uri 	= listFirst(cgi.HTTP_X_REWRITE_URL,'?');	
	else if (structKeyExists(cgi,"HTTP_X_ORIGINAL_URL")) 	// IIS7 URLRewrite
		requested_uri 	= listFirst(cgi.HTTP_X_ORIGINAL_URL,'?');	
	else if (structKeyExists(cgi,"request_uri"))			// apache default
		requested_uri 	= listFirst(cgi.request_uri,'?');	
	else													// apache fallback
		requested_uri 	= listFirst(cgi.redirect_url,'?');
	
	requested_file 	= listLast(requested_uri, "/");
	extension 		= listLast(requested_file, ".");
</cfscript>

<!--- local functions :start --->
<cffunction name="header" returntype="void" output="false">
	<cfargument name="name_value" 	type="string" 	required="false" />
	<cfargument name="status_text" 	type="string" 	required="false" />
	<cfargument name="abort" 		type="boolean" 	required="false" default="false" />
	<cfif structKeyExists(arguments,"name_value") && len(arguments.name_value)>
		<cfheader name="#trim(listFirst(arguments.name_value,":"))#" value="#listRest(arguments.name_value,":")#" />
	<cfelseif structKeyExists(arguments,"status_text") && len(arguments.status_text)>
		<cfheader statuscode="#trim(listFirst(arguments.status_text,":"))#" statustext="#listRest(arguments.status_text,":")#" />
	</cfif>
	<cfif arguments.abort>
		<cfabort />
	</cfif>
</cffunction>

<cffunction name="write_log" returntype="void" output="false">
	<cfargument name="text" 	type="string" required="true" />
	<cfargument name="file" 	type="string" required="false" default="#log_file#" />
	<cfscript>
		if (writeLogs)
			writeLog(file:"#arguments.file#",text:"#arguments.text#")	
	</cfscript>
</cffunction>

<cffunction name="sendImage" returntype="void" output="false">
	<cfargument name="filename" />
	<cfargument name="mime_type" />
	<cfargument name="browser_cache" default="" />
	<cfargument name="error" type="boolean" required="false" default="false" />
	<cfscript>
		header("Content-type:#mime_type#");
		header("Pragma:public");
		if (!arguments.error){
			if (isNumeric(arguments.browser_cache))
				header("Cache-Control:maxage=#arguments.browser_cache#");
			 var fi = getFileInfo(arguments.filename);
				header("Content-Length:#fi.size#");
			 write_log("AI: sending #arguments.filename# with #arguments.mime_type#");
		}
	</cfscript>
	<cfcontent file="#arguments.filename#" type="#arguments.mime_type#" deletefile="#arguments.error#" />
	<cfabort />
</cffunction>

<cffunction name="sendErrorImage" returntype="void" output="false">
	<cfargument name="width" 	type="numeric"	default="200" />
	<cfargument name="height" 	type="numeric"	default="100" />
	<cfargument name="message" 	type="string"	default="Image could not be created" />
	<cfscript>
		// override specific dimensions if they exist in url
		arguments.width 	= structKeyExists(url,"width") ? url.width : arguments.width;
		arguments.height 	= structKeyExists(url,"height") ? url.height : arguments.height;
		var dst 	= imageNew("",arguments.width,arguments.height,"rgb","e5e5e5");
		var attr 	= {
				font 	= "Trebuchet MS",
				style 	= "bold",
				size 	= 14	
			};
		imageSetAntialiasing(dst,"on");
		imageSetDrawingColor(dst, "cc0000");
		imageDrawText(dst,arguments.message,(dst.width/2)-80,(dst.height/2)-(attr.size/2),attr);
		var temp 	= document_root & CreateUUID() & ".png";
		imageWrite(dst,temp);
		sendImage(temp,"image/png",0,true);
	</cfscript>
</cffunction>
<!--- local functions :end --->

<!--- process :start --->
<cfscript>
	write_log("AI: Requested #requested_uri#");
	
	// sort out MIME types for different file types
	switch (extension){ 
	  case "png":
		mime_type = "image/png";
	  break;
	  case "gif":
		mime_type = "image/gif";
	  break;
	  default:
		mime_type = "image/jpeg";
	  break;
	}
	
	// throw 404 or send an image if file does not exists
	if (!fileExists(document_root & requested_uri) || !isImageFile(document_root & requested_uri)){ 
		write_log("AI: Left cuz it didn't exist: #document_root##requested_uri#");
		// to send 404 instead uncomment the next line and comment the sendImageError()
		// header(status_text:"404:Page Not Found",abort:true);
		sendErrorImage(message:"Image does not exists");
	}
	// end: 404

	// if width or height not passed
	if (!structKeyExists(url,"width") && !structKeyExists(url,"height"))
	{
		//If original requested (1st check), no cookie and !mobile first or bad cookie send original
		if(	structKeyExists(url,"original")
			||
			(!structKeyExists(cookie, "resolution") && !mobile_first)
			||
			(structKeyExists(cookie, "resolution") && !isNumeric(cookie.resolution))
		){
			sendImage(document_root & requested_uri,mime_type,browser_cache);
		}
	}
	// end: width/height/original
	
	// resolution set :start
	// work with a requested width and height
	if(structKeyExists(url,"height") && isNumeric(url.height) && structKeyExists(url,"width") && isNumeric(url.width)){
		write_log("AI: url.height=#url.height# and url.width=#url.width#");
		new_width  		= url.width;
		new_height 		= url.height;
		resolution		= 0;
		if (structKeyExists(url,"crop")){
			scale_by 		= "crop"; 
			res_directory	= "c_" & url.width & "_" & url.height;
		}else{
			scale_by 		= "scale"; 
			res_directory	= "s_" & url.width & "_" & url.height;
		}
	}
	// work with a specific height
	else if(structKeyExists(url,"height") && isNumeric(url.height)){
		write_log("AI: url.height=#url.height#");
		resolution		= url.height;
		res_directory	= "h_" & resolution;
		scale_by 		= "height"; 
	}
	// work with a specific width
	else if(structKeyExists(url,"width") && isNumeric(url.width)){
		write_log("AI: url.width=#url.width#");
		resolution		= url.width;
		res_directory	= resolution;
	}
	// work with the cookie value
	else{ 
		write_log("AI: cookie.resolution=#cookie.resolution#");
		for(res in resolutions) {
			write_log("AI: res=#res#");
			if(cookie.resolution <= res) {
				resolution = res; 
				res_directory	= resolution;
			}
		}
	}
	// resolution set :emd
	
	write_log("AI: res=#resolution#");
	
	// set file path to variable
	cache_file = document_root &"/" & cache_path & "/" & res_directory & requested_uri;
	
	write_log("AI: cache #document_root#/#cache_path#/#res_directory#/#requested_uri#");

	// start :doProcess
	// if file exists cached at the requested resolution then serve it back if we are not watching the cache
	if(!watch_cache && fileExists(cache_file)) { 
		write_log("AI: Cache existed");
		sendImage(cache_file,mime_type,browser_cache);
	}
	// it doesn't exist at that size cached - do process
	else{ 
	
		// if cache watching is enabled, compare cache and source modified dates to ensure the cache isn't stale
  		if(watch_cache && fileExists(cache_file)){ 
			
			// get last modified of cached file
			cache_date  = getFileInfo(cache_file).lastmodified; 
			// get last modified of original
			source_date = getFileInfo(document_root & requested_uri).lastmodified;
			
			write_log("AI: watch_cache: #cache_date# to #source_date# ");
			
			// the source file exists and its last modified date is greater than the original 
			if(cache_date > source_date)
				sendImage(cache_file,mime_type,browser_cache);
		}
		
		// continue if image not sent above
			
		// Check the image dimensions
		source_image 	= document_root & requested_uri;
		src 			= imageRead(source_image);
		width 			= imageGetWidth(src);
		height 			= imageGetheight(src);
		
		// Do we need to downscale the image?
		// no, because the width of the source image is already less than the client width
		if(width <= resolution && !compare(scale_by,"width")) { 
			write_log("AI: Width #width# less than res #resolution#");
			sendImage(document_root & requested_uri);
		}
		else if (height <= resolution && !compare(scale_by,"height")){
			write_log("AI: Height #height# less than res #resolution#");
			sendImage(document_root & requested_uri);			
		}
		
		// We need to resize the source image to the width of the resolution breakpoint we're working with
		
		if (!compare(scale_by,"width")){
			ratio      = height/width;
			new_width  = resolution;
			new_height = ceiling(new_width * ratio);
		}else if(!compare(scale_by,"height")){
			ratio      = width/height;
			new_height = resolution;
			new_width  = ceiling(new_height * ratio);			
		}
		
		// set image to new variable
		dst = src;
		
		if (!compare(scale_by,"scale")){
			imageScaleToFit(dst, new_width, new_height,interpolation); // scaled image
		}else if (!compare(scale_by,"crop")){
			if (width > new_width && height > new_height){
				if (new_width < new_height)
					imageScaleToFit(dst, "", new_height,interpolation);
				else
					imageScaleToFit(dst, new_width, "",interpolation);
			}
			x = (dst.width-new_width)/2;
			y = (dst.height-new_height)/2;
			imageCrop(dst, x > 0 ? x : 0, y > 0 ? y : 0, new_width, new_height); // cropped image
		}else{
			imageResize(dst, new_width, new_height,interpolation); // re-sized image
		}
		
		// sharpen the image?
		if(sharpen)
			imageSharpen(dst);
		
		// check the path directory exists and is writable
		// get the directories only
		directory = document_root & "/" & cache_path & "/" & res_directory & replace(requested_uri, "#requested_file#", ""); 
		
		write_log("AI: check:#directory# - exist? #directoryExists(directory)#");
		
		try{
			// does the directory exist already?
			if(!directoryExists(directory)){
				directoryCreate(directory);
				write_log("AI: Made=#directory#");
			}
			
			// save the new file in the appropriate path, and send a version to the browser
			imageWrite(dst, directory & requested_file, jpg_quality/100);
			
			// send image to client
			sendImage(directory & requested_file,mime_type,browser_cache);
		}
		catch(any e){
			write_log("AI: Error Occured : #e.message#");
			sendErrorImage(new_width,new_height);
		}
	
	}
	// end: doProcess
</cfscript>
<!--- process :end --->
