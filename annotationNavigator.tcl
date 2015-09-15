#!/usr/bin/tclsh

package require Tk
package require xml 3.2
package require TclMagick  0.45
package require TkMagick  0.45

source rectangles.tcl

 
set II(left) [image create photo  -format GIF -file left100.gif]
set II(right) [image create photo  -format GIF -file right100.gif]
set I(left) [image create photo  -format GIF -file left.gif]
set I(right) [image create photo  -format GIF -file right.gif]
 
 
namespace eval ::annotatorstate {
	array set nodelist {}
	set workingPath ""
	set workingXMLFile ""
	set workingDOM ""	
	set temp_input ""
	set current_image [image create photo]	
	set current_file ""
	set initialized 0
	namespace eval navigator {
		set numframes 0
		set batchesindex 0
		set current_pos 0
		set current_batch 0
		set upperindex 0
		set tailbound 0
	}
}
set w .t
catch { destroy $w }
toplevel $w
wm title $w "NoLoadedFile"
wm iconname $w "menu"



menubutton $w.menubut -menu $w.menubut.file -text "Annotate" 
$w.menubut configure -anchor w 
menubutton $w.menubuthelp -menu $w.menubuthelp.help -text "Help"

set m $w.menubut.file
menu $m -tearoff 0
grid $w.menubut -row 0 -column 0 -sticky w
grid $w.menubuthelp -row 0 -column 1 -sticky w

$m add command -label "Load Annotation" -command LoadXML 
$m add command -label "Create Annotation" -command CreateXML
$m add command -label "Save New Annotation" -command SaveAsXML
$m add command -label "Move to next" -command MoveNext
$m add command -label "Save Annotation" -command SaveXML
$m add command -label "Exit" -command "exit 0"


set m $w.menubuthelp.help
menu $m -tearoff 0
$m add command -label "About" -command ShowAbout


frame $w.frameshow -borderwidth 10
frame $w.framelabels -borderwidth 10
frame $w.frameprogress -borderwidth 10

grid $w.frameshow -row 1 -column 0
grid $w.frameprogress -row 2 -column 0
grid $w.framelabels -row 3 -column 0

canvas $w.frameshow.canvas -width 320 -height 320 -bg white
set ::canvasstate::mycanvas .t.frameshow.canvas
restore_paint_state 

bind .t.frameshow.canvas <ButtonPress-1> "create_rectangle_normal %x %y"
bind .t.frameshow.canvas <ButtonPress-3> "activate_rectangle %x %y"
bind .t.frameshow.canvas <ButtonPress-2> "restore_paint_state"
bind $w.frameshow.canvas <Key-Prior>  "incrToNextBatch"
bind $w.frameshow.canvas <Key-Next>  "decrToPrevBatch"
bind $w.frameshow.canvas <Key-Right>  "incrToNextFrame"
bind $w.frameshow.canvas <Key-Left>  "decrToPrevFrame"
bind $w.frameshow.canvas <m>  "MoveNext"
bind $w.frameshow.canvas <s>  "SaveXML"
focus $w.frameshow.canvas

pack $w.frameshow.canvas -side top -expand yes -anchor s -fill x  -padx 15


button $w.frameprogress.prevbut -image $I(left) -command "decrToPrevFrame" -height 50 -repeatinterval 100 -repeatdelay 100
button $w.frameprogress.nextbut -image $I(right) -command "incrToNextFrame" -height 50 -repeatinterval 100 -repeatdelay 100
button $w.frameprogress.prev100but -image $II(left) -command "decrToPrevBatch" -height 30 -repeatinterval 100 -repeatdelay 100
button $w.frameprogress.next100but -image $II(right) -command "incrToNextBatch" -height 30 -repeatinterval 100 -repeatdelay 100
scale $w.frameprogress.scale -orient horizontal -length 400 -width 50 -from 0 -to 0 \
	-variable ::annotatorstate::navigator::current_pos -command "updateCurrent"

grid $w.frameprogress.prev100but -row 0 -column 0
grid $w.frameprogress.prevbut -row 0 -column 1
grid $w.frameprogress.scale -row 0 -column 2
grid $w.frameprogress.nextbut -row 0 -column 3 
grid $w.frameprogress.next100but -row 0 -column 4

label $w.framelabels.imagelabel -textvariable ::annotatorstate::current_file 
label $w.framelabels.activitylabel -textvariable ::canvasstate::current_activity
button $w.framelabels.changelabel -text "Change Label" -command "LabelPopup"

grid $w.framelabels.activitylabel -row 0 -column 0
grid $w.framelabels.changelabel -row 0 -column 1
grid $w.framelabels.imagelabel -row 1 -column 0 -columnspan 2

$w.frameprogress.scale set 0

proc SaveXML {} {
	
	puts "Saving XML"
	if { [info exists ::annotatorstate::workingNode]} {	
		saveToXML $::annotatorstate::workingNode
	}
	set data [::dom::DOMImplementation serialize $::annotatorstate::workingDOM -indent 1]
	set fl [open $::annotatorstate::workingXMLFile w]
	puts $fl $data
	close $fl
}

proc MoveNext {} {
	
	foreach mydata $::canvasstate::prev_rectangles {
		puts "v"
		if { [llength $mydata ] == 1 } {
			create_rectangle [lindex $mydata 0] "Unknown"
		} else	{
			create_rectangle [lindex $mydata 0] [lindex $mydata 1]
		}
	}
	
	set ::canvasstate::current_activity $::canvasstate::prev_activity
	set ::canvasstate::prev_rectangles [list ]
}

proc SaveAsXML {} {
	
	if { [info exists ::annotatorstate::workingNode]} {	
		saveToXML $::annotatorstate::workingNode
	}
	set types {
    		{{XML Files}  {.xml}    }
	}
	set filename [tk_getSaveFile -filetypes $types]
	if {$filename == ""} {
    		return
	} else {
		set data [::dom::DOMImplementation serialize $::annotatorstate::workingDOM -indent 1]
		set fl [open $filename w]
		puts $fl $data
		close $fl
	}
	
}

proc LoadXML {} {
	set types {
    		{{XML Files}  {.xml}    }
	}
	set filename [tk_getOpenFile -filetypes $types]
	set ::annotatorstate::workingXMLFile $filename
	if {$filename == ""} {
    		return
	} else {
		LoadData $filename
	}
	
}

proc CreateXML {} {
	
	set dirname [tk_chooseDirectory]
	if {$dirname == ""} {
    		return
	} 
	set doc [::dom::DOMImplementation create]
	set annotator_node [::dom::document createElement $doc Annotator ] 

	if { [ catch { set files [glob "$dirname/*.jpg"] } ] } {
		NoImages
		return
	}
	set files [lsort -increasing $files]
	set index 0

	foreach f $files {
		puts "Scanning $f \n"
		set frame_node [::dom::document createElement $annotator_node Frame ]	
		dom::element setAttribute $frame_node "Activity" "UnknowActivity"
		dom::element setAttribute $frame_node Id $index
		set index [expr {$index +1}]
		set pathlist [file split $f]
		set filename [lindex $pathlist end]
		dom::element setAttribute $frame_node File $filename
	}
	
	
	set types {
    		{{XML Files}  {.xml}    }
	}
	set filename [tk_getSaveFile -initialdir $dirname -filetypes $types]
	if {$filename == ""} {
    		return
	} else	{
		puts "Serializing \n"
		set data [::dom::DOMImplementation serialize $doc -indent 1]		
		set fl [open $filename w]
		puts $fl $data
		close $fl
		puts "Serialized \n"
	}
	
}

proc LoadData { xmlfile } {
	set fl [open $xmlfile]
	set data [read $fl]
	close $fl	
	wm title .t $xmlfile
	set pathlist [file split $xmlfile]
	set pathlist [lreplace $pathlist end end]
	set pathlist [lreplace $pathlist 0 0]
	set path [list "/"]

	if { [info exists ::annotatorstate::workingNode]} {	
		unset ::annotatorstate::workingNode
	}
	foreach chain $pathlist {
		set path [linsert $path end $chain]
		set path [linsert $path end "/"]		
	}	
	
	set ::annotatorstate::workingpath [join $path ""]
	set ::annotatorstate::initialized 0
	ProcessXML $data
}

proc initializeNavigator {} {
	puts "init"
	set sizer [array size ::annotatorstate::nodelist]
	puts "we have $sizer"
	set ::annotatorstate::navigator::numframes $sizer
	set sizer [expr {$sizer - 1}]		
	set ::annotatorstate::navigator::current_batch 0
	set ::annotatorstate::navigator::batchesindex [expr {$sizer / 100}]
	set ::annotatorstate::navigator::tailbound [expr {$sizer % 100}]
	if {$::annotatorstate::navigator::batchesindex == 0 } {
		set ::annotatorstate::navigator::upperindex $::annotatorstate::navigator::tailbound
	} else {
		set ::annotatorstate::navigator::upperindex 99
	}
	.t.frameprogress.scale configure -from 0
	.t.frameprogress.scale configure -to $::annotatorstate::navigator::upperindex
	set ::annotatorstate::navigator::current_pos 0	
}

proc incrToNextFrame {} {
	puts "incrToNextFrame" 
	set sizer $::annotatorstate::navigator::upperindex	
	set pos [expr { $::annotatorstate::navigator::current_pos +1 }]
	if { $pos > $sizer }  {
		return
	}
	updateCurrent $pos
}

proc decrToPrevFrame {} {
	puts "decrToPrevFrame" 
	set pos [expr { $::annotatorstate::navigator::current_pos - 1 }]
	if { $pos < 0 } {
		return
	}
	updateCurrent $pos
}

proc incrToNextBatch {} {
	puts "incrToNextBatch" 
	set sizer $::annotatorstate::navigator::batchesindex
	set nextbatch [expr { $::annotatorstate::navigator::current_batch + 1}]
	
	if { $nextbatch > $sizer } {
		puts "$nextbatch  $sizer"
		return
	}
	
	puts "doif"
	if { $nextbatch == $sizer } {
			
		set ::annotatorstate::navigator::upperindex $::annotatorstate::navigator::tailbound 
	} else {
		
		if { $nextbatch < $sizer } {
			set ::annotatorstate::navigator::upperindex 99
		}
	}	
	set ::annotatorstate::navigator::current_batch $nextbatch	
	.t.frameprogress.scale configure -from 0
	.t.frameprogress.scale configure -to $::annotatorstate::navigator::upperindex
	updateCurrent 0
}

proc decrToPrevBatch {} {
	puts "decrToPrevBatch" 
	set sizer $::annotatorstate::navigator::batchesindex
	set prevbatch [expr { $::annotatorstate::navigator::current_batch - 1}]
	if { $prevbatch < 0 } {	
		puts "$prevbatch  $sizer"
		return
	}
	puts "doif"
	set ::annotatorstate::navigator::upperindex 99
	set ::annotatorstate::navigator::current_batch $prevbatch
	.t.frameprogress.scale configure -from 0
	.t.frameprogress.scale configure -to $::annotatorstate::navigator::upperindex
	updateCurrent 0
}

proc updateCurrent {pos} {
	puts "update"
	if { $::annotatorstate::navigator::numframes == 0} {
		puts "AKyro"
		return
	}
	set ::annotatorstate::navigator::current_pos $pos
	LoadImage 	
}

proc ProcessXML {data} {
	puts "Process xml" 
	set ::annotatorstate::workingDOM [dom::parse $data]
	set somenode [dom::selectNode $::annotatorstate::workingDOM /*]
	set framenodes [dom::selectNode $somenode child::* ]
	
	array set  ::annotatorstate::nodelist {}
	
	set count 0
	foreach framenode $framenodes {
		
		set ::annotatorstate::nodelist($count) $framenode
		set count [expr {$count + 1}]
	}
	initializeNavigator	
	LoadImage
}

proc LoadImage {} {
	puts "Load"
	if { [info exists ::annotatorstate::workingNode]} {	
		saveToXML $::annotatorstate::workingNode
	}
	restore_canvas_state
	set pos [expr {$::annotatorstate::navigator::current_pos + 100 * $::annotatorstate::navigator::current_batch}]	
	set ::annotatorstate::workingNode $::annotatorstate::nodelist($pos)
	set filename [::dom::element getAttribute $::annotatorstate::workingNode File]
	set Id [::dom::element getAttribute $::annotatorstate::workingNode  Id]
	set Activity [::dom::element getAttribute $::annotatorstate::workingNode Activity]
	
	set filename [join [list $::annotatorstate::workingpath $filename] ""]
	set temp [magick create wand]
	$temp  ReadImage $filename	
	magicktophoto $temp $::annotatorstate::current_image
		
	if { $::annotatorstate::initialized == 0} {
        	set ::annotatorstate::initialized 1	
        	.t.frameshow.canvas configure -width [$temp width]
        	.t.frameshow.canvas configure -height [$temp height]	
        	.t.frameshow.canvas create image 0 0  -anchor nw  \
        			-image $::annotatorstate::current_image \
        			-tag ::annotatorstate::current_image
	}
	
	magick delete $temp	
	create_rectangle_XML $::annotatorstate::workingNode
	set ::annotatorstate::current_activity "$Activity"
	set ::annotatorstate::current_file "$filename"
}

proc LabelPopup {} {

	set sizer [array size ::annotatorstate::nodelist]
	if { $sizer == 0 } {
		return
	}
	toplevel .messpop -width 10c -height 4c
	grab .messpop
	wm title .messpop "Change label"

	set ::annotatorstate::temp_input $::canvasstate::current_activity
	entry .messpop.someentry -state normal -textvariable ::annotatorstate::temp_input

	button .messpop.okb -text OK\
		-command {destroy .messpop ; \
				set ::canvasstate::current_activity $::annotatorstate::temp_input ; \
				set  return 0}
		
	button .messpop.cancelb -text Cancel \
		-command {destroy .messpop ;  return 0}
	
	grid .messpop.someentry -row 0 -column 0 -columnspan 2
	grid .messpop.okb -row 1 -column 0
	grid .messpop.cancelb -row 1 -column 1 
}



proc ShowAbout {} {
	toplevel .messpop
	wm title .messpop "About ScovisAnnotator"
	label .messpop.lab -text "A simple frame sequence annotator. \n \
				Author : Vasileios Anagnostopoulos \n \
				For the purposes of Scovis EU project."
	pack .messpop.lab
	button .messpop.cancelb -text "Thanks Vasileios" \
		-command {destroy .messpop ;  return 0}
	pack .messpop.cancelb
}

proc NoImages {} {
	toplevel .messpop
	wm title .messpop "no Images found"
	label .messpop.lab -text "You selected an directory containg no jpeg files."
	pack .messpop.lab
	button .messpop.cancelb -text "OK" \
		-command {destroy .messpop ;  return 0}
	pack .messpop.cancelb
}
