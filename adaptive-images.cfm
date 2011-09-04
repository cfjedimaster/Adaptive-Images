<cflog file="application" text="AI: Running">

<cffunction name="header">
	<cfargument name="namevalue" type="string" required="true">
	<cfheader name="#trim(listFirst(arguments.namevalue,":"))#" value="#listRest(arguments.namevalue,":")#">
</cffunction>

<cffunction name="sendImage">
	<cfargument name="filename">
	<cfargument name="mime_type">
	<cfargument name="browser_cache" default="">
	<cfheader name="Content-type" value="#mime_type#">
	<cfheader name="Pragma" value="public">
	<cfif isNumeric(arguments.browser_cache)>
		<cfheader name="Cache-Control" value="maxage=#arguments.browser_cache#">
		<!---
	    //header('Expires: '.gmdate('D, d M Y H:i:s', time()+$browser_cache).' GMT');
		--->
	</cfif>
	<cfset var fi = getFileInfo(arguments.filename)>
	<cfheader name="Content-Length" value="#fi.size#">
	<cflog file="application" text="sending #arguments.filename# with #arguments.mime_type#">
	<cfcontent file="#arguments.filename#" type="#arguments.mime_type#">
	<cfabort>
</cffunction>

<cfscript>
resolutions 	= [1382,992,768,430]; // the resolution break-points to use (screen widths, in pixels)
cache_path		= "ai-cache"; // where to store the generated re-sized images. This folder must be writable.
jpg_quality 	= 80; // the quality of any generated JPGs on a scale of 0 to 100
sharpen     	= TRUE; // Shrinking images can blur details, perform a sharpen on re-scaled images?
watch_cache 	= TRUE; // check that the responsive image isn't stale (ensures updated source images are re-cached)
browser_cache 	= 60*60*24*7; // How long the BROWSER cache should last (seconds, minutes, hours, days. 7days by default)
mobile_first	= true; // If there's no cookie deliver the mobile version (if FALSE, delivers original resource)

document_root  = expandPath("/");
requested_uri = cgi.redirect_url;
requested_file = listLast(requested_uri, "/");
writelog(file="application", text="AI: Requested #requested_uri#");
extension = listLast(requested_file, ".");

switch (extension){ // sort out MIME types for different file types
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

if (!fileExists(document_root & requested_uri)){ // and the requested file doesn't exist either
	writelog(file="application", text="AI: Left cuz it didn't exist: #document_root##requested_uri#");
	header("Status: 404 Not Found");
	abort;
}

//If no cookie and !mobile first or bad cookie send original
if(
	(!structKeyExists(cookie, "resolution") && !mobile_first)
	||
	(structKeyExists(cookie, "resolution") && !isNumeric(cookie.resolution))) {

    sendImage(document_root & requested_uri,mime_type,browser_cache);

}

arraySort(resolutions, "numeric","desc"); // make sure the supplied break-points are in ascending size order
resolution = resolutions[1]; //This is the default

if(structKeyExists(cookie, "resolution")){ 
	writelog(file="application",text="AI: cookie.resolution=#cookie.resolution#");
	client_width = cookie.resolution; // store the cookie value in a variable

	for(res in resolutions) {
		writelog(file="application",text="res=#res#");
		if(client_width <= res) resolution=res; 
	}
}

writelog(file="application", text="AI: res=#resolution#");
writelog(file="application", text="AI: cache #document_root#/#cache_path#/#resolution#/#requested_uri#");
if(fileExists(document_root & "/#cache_path#/#resolution#/"&requested_uri)) { // it exists cached at that size
  writelog(file="application", text="AI: Cache existed");
  sendImage(document_root&"/#cache_path#/#resolution#/"&requested_uri,mime_type,browser_cache);
}
else { // it doesn't exist at that size cached

  if(watch_cache) { // if cache watching is enabled, compare cache and source modified dates to ensure the cache isn't stale

	cache_file = document_root &"/" & cache_path & "/" & resolution &"/" & requested_uri;
	if(fileExists(cache_file)) cache_date  = getFileInfo(cache_file).lastmodified;
    source_date = getFileInfo(document_root & requested_uri).lastmodified;
	//writelog(file="application", text="cmp #cache_date# to #source_date# ");
    if(!fileExists(cache_file) || cache_date < source_date) { // the source file has been replaced since the cache was generated
      // Check the image dimensions
      source_image = document_root & requested_uri;
	  src = imageRead(source_image);
	  width = imageGetWidth(src);
	  height = imageGetheight(src);

      // Do we need to downscale the image?
      if(width <= resolution) { // no, because the width of the source image is already less than the client width
		writeLog(file="application", text="Width #width# less than res #resolution#");
        sendImage(document_root & requested_uri);
      }

      // We need to resize the source image to the width of the resolution breakpoint we're working with
      ratio      = height/width;
      new_width  = resolution;
      new_height = ceiling(new_width * ratio);

	  dst = src; //Need to change this
	  imageResize(dst, new_width, new_height); // re-sized image
      //ImageCopyResampled($dst, $src, 0, 0, 0, 0, $new_width, $new_height, $width, $height); // do the resize in memory

      // sharpen the image?
      if(sharpen == TRUE) {
		imageSharpen(dst);
      }

      // check the path directory exists and is writable
	  directories = replace(requested_uri, "/#requested_file#", ""); // get the directories only
      directories = right(directories, len(directories)-1); // clean the string
	  writelog(file="application", text="AI: directories=#directories#, to check:#document_root#/#cache_path#/#resolution#/#directories# - exisT? #directoryExists("#document_root#/#cache_path#/#resolution#/#directories#")#");

      if(!directoryExists("#document_root#/#cache_path#/#resolution#/#directories#")){ // does the directory exist already?
        /*
		if (!mkdir("$document_root/$cache_path/$resolution/$directories", 0777, true)) { // make the directory
          // uh-oh, failed to make that directory
          ImageDestroy($src); // clean-up after ourselves
          ImageDestroy($dst); // clean-up after ourselves

          // notify the client by way of throwing a message in a bottle, as that's all we can do 
          $im         = ImageCreateTrueColor(800, 200);
          $text_color = ImageColorAllocate($im, 233, 14, 91);
          ImageString($im, 1, 5, 5,  "Failed to create directories: $document_root/$cache_path/$resolution/$directories", $text_color);
          header("Pragma: public");
          header("Cache-Control: maxage=" & $browser_cache);
          header('Expires: ' & gmdate('D, d M Y H:i:s', time()+$browser_cache) & ' GMT');
          header('Content-Type: image/jpeg');
          ImageJpeg($im); ImageDestroy($im);
          exit();
        }
		*/
		//create the dir - handle errors later
		directoryCreate("#document_root#/#cache_path#/#resolution#/#directories#");
		writelog(file="application",text="AI: Made=#document_root#/#cache_path#/#resolution#/#directories#");
      }

      // save the new file in the appropriate path, and send a version to the browser
	  imageWrite(dst, "#document_root#/#cache_path#/#resolution#/#directories#/#requested_file#");

	  /*
      if(!$gotSaved) {
        // Couldn't save image, notify the client by way of throwing a message in a bottle, as that's all we can do 
        $im         = ImageCreateTrueColor(800, 200);
        $text_color = ImageColorAllocate($im, 233, 14, 91);
        ImageString($im, 1, 5, 5,  "Failed to create directories: $document_root/$cache_path/$resolution/$directories", $text_color);
        header('Content-Type: image/jpeg');
        ImageJpeg($im); ImageDestroy($im);
        exit();
      }
      else { // we saved the image to cache, now deliver the image to the client
      */  
		//ImageDestroy($src); ImageDestroy($dst);
        sendImage("#document_root#/#cache_path#/#resolution#/#directories#/#requested_file#",mime_type,browser_cache);
      /*}*/
    }

  } // end of if watch-cache
	
	
} // end it doesn't exist at the mobile size cached
</cfscript>