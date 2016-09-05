# encoding: UTF-8
require 'nokogiri'
require 'state_machine'
require 'logger'
require 'set'
require 'rubygems'
require 'zip/zip'
require 'fileutils'

require './settings'
require './figure_config'

# Lists of styles 
# allowed in source Word documents (the "all" list)

$all_styles= Set.new [
	"Question",
	"Label",
	"Bloom",
	"Concepts",
	"Answer",
	"Answer-bulleted",
	"Answer-numbered",
	"Figure",
	"Figure-ID",
	"Figure-caption"
]

$figure_related_styles= Set.new [
	"Figure",
	"Figure-ID",
	"Figure-caption"		
]

$list_styles= Set.new [
	"Answer-bulleted",
	"Answer-numbered"
]

$bulleted_style =  ["Answer-bulleted"]
$numbered_style =  ["Answer-numbered"]

$core_styles= Set.new [
	"Question",
	"Bloom",
	"Concepts",
	"Answer"
]

$non_textual_styles = Set.new [
	"Figure"
]

$textual_styles = Set.new [
	"Question",
	"Label",
	"Bloom",
	"Concepts",
	"Answer",
	"Answer-bulleted",
	"Answer-numbered",
	"Figure-ID",
	"Figure-caption"
]

$figure_style = "Figure"

# ALEF tag constants (just to keep the configuration separated)
$target_italic_open = '<emphasis>'
$target_italic_close = '</emphasis>'
$target_bold_open = '<emphasis role="bold">'
$target_bold_close = '</emphasis>'


#This class reads an MS Word XML file,
#finds relevant nodes (determining their styles), 
#handles formatting markup (bolds, italics), 
#removes comments (they should be dropped by the way, as they are only anchored in the markup (with special tags))
#translates markup to ALEF markup
# finally, it leaves list of paragraphs with necessary info in the "paragraphs" attribute
class Paragraph_reader
	attr_accessor :paragraphs
	
	def initialize(filepath)
		p 'initial processing '+ filepath
		@paragraphs = []
		@number_of_images = 0
		file = File.open(filepath, 'r')
		file_content = file.read
		@doc = Nokogiri::XML(file_content)
		@doc.remove_namespaces!
		@doc.xpath("//p").each do |parnode|
			if parnode.at_xpath(".//pStyle") == nil then
				error_message = "Found normal styled paragraph in " 
				error_message += File.basename(filepath,".document.xml").encode($encoding_environment)
				error_message += ", starting with '"
				if parnode.xpath(".//r").empty? 
					then some_paragraph_text = "[No Text]"
					else some_paragraph_text = parnode.xpath(".//r")[0].content 
				end
				error_message += some_paragraph_text.encode($encoding_environment )
				error_message +="'"
				$log.error  error_message
				next
			end
			current_style = parnode.at_xpath(".//pStyle")["val"]
			
			next unless $all_styles.include? current_style 
			
			# put together textual content, handle bolds and italics
			textual_content = ""
			if $textual_styles.include? current_style then
				# iterate through text parts within the paragraph and compose a single string of it
				# add ALEF bold and italic markup, if found
				parnode.xpath(".//r").each do |runningnode|
					textnode = runningnode.at_xpath("t")
					text = ""
					text = textnode.content unless textnode == nil
					if runningnode.at_xpath(".//i")!=nil then text = $target_italic_open + text + $target_italic_close end					
					if runningnode.at_xpath(".//b")!=nil then text = $target_bold_open + text + $target_bold_close end
					text.gsub!(/\u00a0/, ' ') # remove hard space
					text.gsub!(/\u202F/, ' ') # remove hard space
					text.gsub!(/\u000A/, ' ') # replace line breaks with space (TODO (maybe with double backslash, for LaTeX))
					text.gsub!('~\cite', '\nocite') # flip ~\cite to \nocite 
					text.gsub!('\cite', '\nocite') # flip \cite to \nocite 
					text.gsub!('\reallycite', '\cite') # enable nocite override
					textual_content << text
				end
			end
			
			#handle figure
			image_source = nil
			image_id = nil
			if $figure_style == current_style then
				@number_of_images +=1
				blip = parnode.xpath(".//blip").first
				p blip
				#Najst spravny subor pomocou mapovania ulozeneho v samostatnom subore rels
				rels_file = File.open(filepath+".rels",'r')
				rels_xml = Nokogiri::XML(rels_file.read)
				rels_xml.remove_namespaces!
				relationship = rels_xml.xpath('.//Relationship[@Id="'+blip[:embed]+'"]').first			
				rels_file.close
				image_path= File.join(File.dirname(filepath), File.basename(filepath,".document.xml") +'.images' ,File.basename(relationship[:Target]))				
				image_source = image_path
				image_id = blip[:embed]
			end
			
			paragraph = {:type => :regular, :style => current_style, :text => textual_content, :source => image_source, :image_id => image_id}
			@paragraphs <<  paragraph		
		end
	end
	
end


# This class acts as a state machine for construction of QALOs. As input, it takes paragraphs in ALEF markup as parametrized events.
# Example:
# extractor.question_found (params)
# extractor.answer_fourd (params)
class Extractor
	attr_accessor :qalos, :original_file_path
	
	def initialize
		@qalos = []
		super()
	end
	
	def method_missing(method_sym, *arguments, &block)
		super unless method_sym.to_s.include? '_found'
	end
  
	state_machine :state, :initial => :state_preamble do
		
		# STATES
		state :state_preamble do
		end
		
		state :state_question do
		end
		
		state :state_bloom do
		end
		
		state :state_concepts do
		end
		
		state :state_answer do
		end
		
		state :state_finalized do
		end
		
		# EVENTS
		
		event :question_found do
			transition :state_preamble => :state_question, :state_answer => :state_question, :state_concepts => :state_question, :state_bloom => :state_question, :state_question => :state_question
		end
		
		event :label_found do
			transition :state_question => :state_question
		end

		event :bloom_found do
			transition :state_question => :state_bloom, :state_bloom => :state_bloom
		end
		
		event :concepts_found do
			transition :state_bloom => :state_concepts, :state_question => :state_concepts, :state_concepts => :state_concepts
		end
		
		event :answer_found do
			transition :state_concepts => :state_answer, :state_bloom => :state_answer, :state_question => :state_answer, :state_answer => :state_answer
		end
		
		event :figure_completed do
			transition :state_question => :state_question, :state_answer => :state_answer
		end
		
		event :bulleted_completed do
			transition :state_answer => :state_answer
		end
		
		event :numbered_completed do
			transition :state_answer => :state_answer
		end	

		event :finalize do
			transition any => :state_finalized
		end
		
		# ACTION HOOKS
		
		#happy day
		after_transition any - :state_question => :state_question, :do => [:begin_QALO, :append_question_par]
		around_transition :state_question => :state_question, :on => :question_found, :do => [:append_question_par]
		around_transition :state_question => :state_question, :on => :figure_completed, :do => [:append_question_figure]
		around_transition :state_question => :state_question, :on => :label_found, :do => [:assign_question_label]
		after_transition :state_question => :state_bloom, :do => [:process_bloom]
		after_transition :state_bloom => :state_concepts, :do => [:process_concepts]
		after_transition :state_concepts => :state_answer, :do => [:append_answer_par]
		around_transition :state_answer => :state_answer,  :on => :answer_found, :do => [:append_answer_par]
		around_transition :state_answer => :state_answer, :on => :figure_completed, :do => [:append_answer_figure]
		around_transition :state_answer => :state_answer, :on => :bulleted_completed, :do => [:append_answer_bulleted]
		around_transition :state_answer => :state_answer, :on => :numbered_completed, :do => [:append_answer_numbered]
		before_transition :state_answer => :state_question, :do => [:conclude_QALO]
		after_transition any => :state_finalized, :do => [:conclude_QALO]
		
		#deviations
		around_transition :state_bloom => :state_bloom, :do => [:redundant_bloom]
		
		around_transition :state_concept => :state_concept, :do => [:redundant_concepts]
		before_transition :state_question => :state_concepts, :do => [:missing_bloom, :process_concepts]
		
		before_transition :state_bloom => :state_answer, :do => [:missing_concepts, :append_answer_par]
		before_transition :state_question => :state_answer, :do => [:missing_bloom, :missing_concepts, :append_answer_par]
		
		before_transition :state_bloom => :state_question, :do => [:missing_concepts, :conclude_QALO]
		before_transition :state_question => :state_finalized, :do => [:missing_bloom, :missing_concepts]		
		before_transition :state_bloom => :state_finalized, :do => [:missing_concepts]		
	end	
		
	# ACTIONS (effects)	
	
	def begin_QALO
		@QALO = {:question => [], :bloom => "0", :concepts => [], :answer => []}
		$log.debug "New QALO started"
	end
	
	def append_question_par(transition)
		par = transition.args[0]
		@QALO[:question] << par
		$log.debug "Added question paragraph"
	end

	def append_question_figure(transition)
		par = transition.args[0]
		@QALO[:question] << par
		$log.debug "Added question figure"
	end
	
	def assign_question_label(transition)
		par = transition.args[0]
		@QALO[:label] = par[:text]
		$log.debug "Assigned question label"
	end

	def process_bloom(transition)
		text = transition.args[0][:text]
		@QALO[:bloom] = /\d+/.match(text).to_s
		$log.debug "Identified bloom taxonomy level"
	end

	def process_concepts(transition)
		text = transition.args[0][:text]
		tags = text.split(',').map(&:strip)#.map(&:downcase)
		@QALO[:concepts] = tags
		$log.debug "Identified concepts"		
	end

	def append_answer_par(transition)
		par = transition.args[0]
		@QALO[:answer] << par
		$log.debug "Added answer paragraph"		
	end

	def append_answer_figure(transition)
		par = transition.args[0]
		@QALO[:answer] << par
		$log.debug "Added answer figure"
	end

	def append_answer_bulleted(transition)
		par = transition.args[0]
		@QALO[:answer] << par
		$log.debug "Added bulleted paragraph"				
	end

	def append_answer_numbered(transition)
		par = transition.args[0]
		@QALO[:answer] << par
		$log.debug "Added numbered paragraph"			
	end

	def conclude_QALO
		@qalos << @QALO unless @QALO == nil
		$log.debug "TODO uzavriet doteraz zaznamenavane QALO"
	end
	
	def missing_bloom
		$log.debug "TODO handle missing bloom"
	end
	
	def missing_concepts
		$log.debug "TODO handle missing concepts"
	end
	
	def redundant_bloom
		$log.debug "TODO redundant bloom level declaration"
	end

	def redundant_concepts
		$log.debug "TODO rednundant concept paragraph (use just one paragraph)"
	end
	

end


class Bulleted_list_detector
	
	def initialize(extractor)
		@extractor = extractor
		super()
	end
	
	def method_missing(method_sym, *arguments, &block)
		unless method_sym.to_s.include? '_found' then 
			super
			return
		end
		other_found
	end
	
	state_machine :state, :initial => :state_nothing do
		
		# STATES
		state :state_nothing do
		end
		
		state :state_list do
		end
		
		# EVENTS
		
		event :'answer-bulleted_found' do
			transition :state_nothing => :state_list, :state_list => :state_list
		end
		
		event :other_found do
			transition :state_list => :state_nothing, :state_nothing => :state_nothing
		end
		
		# ACTION HOOKS
		
		after_transition :state_nothing => :state_list, :do => [:bulleted_started, :bulleted_continued]
		around_transition :state_list => :state_list, :do => [:bulleted_continued]
		before_transition :state_list => :state_nothing, :do => [:bulleted_completed]
				
	end	
		
	# ACTIONS (effects)	
	
	def bulleted_started
		@list = []
		$log.debug "New bulleted list started"
	end
	
	def bulleted_continued(transition)
		line = transition.args[0][:text]
		@list << line
		$log.debug "Bullet added"
	end
	
	def bulleted_completed
		result = {:type => :bulleted, :style => $bulleted_style[0], :list => @list}
		@extractor.bulleted_completed result
		$log.debug "Bulleted list completed"		
	end

end


class Numbered_list_detector
	def initialize(extractor)
		@extractor = extractor
		super()
	end
	
	def method_missing(method_sym, *arguments, &block)
		unless method_sym.to_s.include? '_found' then 
			super
			return
		end
		other_found
	end
	
	state_machine :state, :initial => :state_nothing do
		
		# STATES
		state :state_nothing do
		end
		
		state :state_list do
		end
		
		# EVENTS
		
		event :'answer-numbered_found' do
			transition :state_nothing => :state_list, :state_list => :state_list
		end
		
		event :other_found do
			transition :state_list => :state_nothing, :state_nothing => :state_nothing
		end
		
		# ACTION HOOKS
		
		after_transition :state_nothing => :state_list, :do => [:numbered_started, :numbered_continued]
		around_transition :state_list => :state_list, :do => [:numbered_continued]
		before_transition :state_list => :state_nothing, :do => [:numbered_completed]
				
	end	
		
	# ACTIONS (effects)	
	
	def numbered_started
		@list = []
		$log.debug "New numbered list started"
	end
	
	def numbered_continued(transition)
		line = transition.args[0][:text]
		@list << line
		$log.debug "Numbered item added"
	end
	
	def numbered_completed
		result = {:type => :numbered, :style => $numbered_style[0], :list => @list}
		@extractor.numbered_completed result
		$log.debug "Numbered list completed"		
	end
end



class Figure_detector
	def initialize(extractor)
		@extractor = extractor
		super()
	end
	
	def method_missing(method_sym, *arguments, &block)
		unless method_sym.to_s.include? '_found' then 
			super
			return
		end
		other_found unless $figure_related_styles.include? method_sym.to_s
	end
	
	state_machine :state, :initial => :state_nothing do
		
		# STATES
		state :state_nothing do
		end
		
		state :state_figure_detected do
		end
		
		state :state_figure_identified do
		end
		
		# EVENTS
		
		event :'figure_found' do
			transition :state_nothing => :state_figure_detected, :state_figure_detected => :state_figure_detected
		end
		
		event :'figure-id_found' do
			transition :state_figure_detected => :state_figure_identified, :state_nothing => :state_nothing, :state_figure_identified => :state_figure_identified
		end

		event :'figure-caption_found' do
			transition :state_figure_identified => :state_nothing, :state_figure_detected => :state_nothing, :state_nothing => :state_nothing
		end
		
		event :other_found do
			transition :state_figure_identified => :state_nothing, :state_figure_detected=> :state_nothing
		end
		
		# ACTION HOOKS
		
		#happy day
		after_transition :state_nothing => :state_figure_detected, :on => :figure_found, :do => [:start_figure, :add_figure_source]
		after_transition :state_figure_detected => :state_figure_identified, :on => :'figure-id_found', :do => [:add_figure_ID]
		before_transition :state_figure_identified => :state_nothing, :on => :'figure-caption_found', :do => [:add_figure_caption, :complete_figure]
		
		#deviations
		around_transition :state_figure_detected => :state_figure_detected, :on => :figure_found, :do => [:caption_missing, :ID_missing, :complete_figure, :start_figure, :add_figure_source]
		around_transition :state_nothing => :state_nothing, :on => :'figure-id_found', :do => [:orphaned_ID]
		before_transition :state_figure_detected => :state_nothing, :on => :'figure-caption_found', :do => [:ID_missing, :add_figure_caption, :complete_figure]
		around_transition :state_nothing => :state_nothing, :on => :'figure-caption_found', :do => [:orphaned_caption]
		before_transition :state_figure_identified => :state_nothing, :on => :other_found, :do => [:caption_missing, :complete_figure]
		before_transition :state_figure_detected => :state_nothing, :on => :other_found, :do => [:ID_missing, :caption_missing, :complete_figure]
		around_transition :state_figure_identified => :state_figure_identified, :on => :'figure-id_found', :do => [:multiple_ID] 		
	end
			
	# EVENT OVERRIDES
	#def figure_found (par)
	#	super
	#end	
		
	# ACTIONS (effects)
	
	def  ID_missing
		$log.warn "TODO ID missing"
	end
	
	def  caption_missing
		$log.warn "TODO caption missing"
	end
	
	def  start_figure
		@figure_info = {:type => :figure, :source => nil, :ID => nil, :caption => nil}
		$log.debug "New figure started"
	end
	
	def add_figure_source (transition)
		@figure_info[:source] = transition.args[0][:source]
		$log.debug "Add figure source"
	end
	
	def add_figure_ID (transition)
		@figure_info[:ID] = transition.args[0][:text]
		$log.debug "Add figure ID"
	end
	
	def add_figure_caption (transition)
		@figure_info[:caption] = transition.args[0][:text]
		$log.debug "Add figure caption"
	end
	
	def  complete_figure
		@extractor.figure_completed @figure_info
		$log.debug "Figure completed"
	end
	
	def orphaned_ID
		$log.warn "TODO orphaned figure ID"
	end
	
	def multiple_ID
		$log.warn "TODO an ID for a figure was defined multiple times, ignoring all except the first"
	end
	
	def orphaned_caption
		$log.warn "TODO orphaned figure caption"
	end
	
end


#ALEF  docbook builder
class Docbook_builder
	
	#ALEF specific XML builder
	#builds the XML LO file + copies necessary figure files
	def build_ALEF_resource filename, qalo
		@figure_id = 0
		@actual_qalo = qalo
		b = Nokogiri::XML::Builder.new(:encoding => 'utf-8') do |xml|
			xml.article('xmlns' => 'http://docbook.org/ns/docbook', 
			'xmlns:html' => 'http://www.w3.org/1999/xhtml', 
			'xmlns:alef' => 'http://fiit.stuba.sk/ns/alef', 
			'version' => '5.0', 
			'role' => 'question', 
			'xml:id' => qalo[:id], 
			'difficulty' => '1',    #TODO Vieme aj inak
			'bloom' => qalo[:bloom]){
				xml.title qalo[:concepts].first
				xml.metadata {
					qalo[:concepts].each { |tag| xml.tag tag}
				}
				xml.simpleselect ({'role' => 'definition'}) {
					qalo[:question].each do |par|
						self.send("append_"+(par[:type].to_s), xml, par)
					end
				}
				xml.simpleselect ({'role' => 'solution'}) {
					qalo[:answer].each do |par|
						self.send("append_"+(par[:type].to_s), xml, par)
					end					
				}
			}
		end
		File.open(filename, 'w') {|f| f.write(b.to_xml) }
	end
	
	def append_regular (xml, par)
		xml.para { xml << par[:text] }
	end
	
	#also copies image files to ALEF resource folder
	def append_figure (xml, par)
		@figure_id+=1
		format = File.extname(par[:source])
		figure_target_filename = @actual_qalo[:id] + '-figure-' + @figure_id.to_s + format
		p "fig fig fig " + figure_target_filename
		begin
			FileUtils.copy_file(par[:source], File.join($output_folder_docbook_resources, figure_target_filename))
		rescue
			p "sakra"
		end
		xml.informalfigure ({'xml:id' => par[:ID]}) {
			xml.mediaobject {
				xml.imageobject {
					xml.imagedata ({'format' => format[1..-1], 'fileref' => File.join($docbook_resource_folder_relative, figure_target_filename) })
				}
				xml.caption {
					xml.para par[:caption]
				}
			}
		}
	end
	
	def append_bulleted (xml, par)
		xml.itemizedlist {
			par[:list].each { |item|
				xml.listitem { 
					xml.para { xml << item }
				}
			}
		}
	end
	
	def append_numbered (xml, par)
		xml.orderedlist {
			par[:list].each { |item|
				xml.listitem { 
					xml.para { xml << item }
				}
			}
		}		
	end
	
end


class Zipper
	# plain and simple unzip
	def unzip_file (file, destination)
		logfile = File.open("unzip_logfile.txt",'w')
		Zip::ZipFile.open(file) { |zip_file|
			zip_file.each { |f|
				name = f.name
				p name.force_encoding('ASCII-8BIT')
				logfile.puts f.name
				f_path=File.join(destination, f.name)
				#p (f_path.encoding.to_s + " " + File.basename(f_path))
				#f_path = f_path.encode('Windows-1250')
				#p f_path
				FileUtils.mkdir_p(File.dirname(f_path))
				zip_file.extract(f, f_path) unless File.exist?(f_path)
			}
		}
		logfile.close
	end
	
	# unzipne docx, vytiahne XMLko s obsahom dokumentu a ulozi ho pod rovnakym nazvom do zadaneho priecinka
	# zaroven unzipne aj vsetky obrazky do priecinka pomenovaneho suffixom .images
	def unzip_word_XML(file, destination)
		#p 'unzipping '+file
		#Unzip content
		Zip::ZipFile.open(file) { |zip_file|
			zip_file.each { |f|
				unless f.name == "word/document.xml" then next end
				f_path=File.join(destination, File.basename(file,".docx")+".document.xml")
				#FileUtils.mkdir_p(File.dirname(f_path))
				#f_path = f_path.encode($encoding_environment)
				#p f_path
				zip_file.extract(f, f_path) unless File.exist?(f_path)
			}
		}	
		#Unzip relationships
		Zip::ZipFile.open(file) { |zip_file|
			zip_file.each { |f|
				unless f.name == "word/_rels/document.xml.rels" then next end
				f_path=File.join(destination, File.basename(file,".docx")+".document.xml.rels")
				#FileUtils.mkdir_p(File.dirname(f_path))
				#f_path = f_path.encode($encoding_environment)
				p f_path
				p f.name
				zip_file.extract(f, f_path) unless File.exist?(f_path)
			}
		}	
		Zip::ZipFile.open(file) { |zip_file|
			zip_file.each { |f|
				unless f.name.include? 'word/media/image' then next end
				f_path=File.join(destination, File.basename(file,".docx")+".images", File.basename(f.name))
				FileUtils.mkdir_p(File.dirname(f_path))			
				zip_file.extract(f, f_path) unless File.exist?(f_path)
				#p "unzipped " + f_path
			}
		}	
	end
end

class Latexer
	
	def initialize

	end
	
	def build_master_file
		File.open($output_folder_latex+'/master.tex',"w") do |file|
			file.puts 	'\documentclass[twoside]{book}'
			file.puts  	'\usepackage{knizka}'
			file.puts  	'\addbibresource{all_bibliography_sources}'
			file.puts  	'\begin{document}'
			file.puts 	'\pagenumbering{roman}'
			file.puts  	'\input{titlepage.tex}'
			file.puts  	'\tableofcontents'
			file.puts  	'\listofquestion'
			file.puts  	'\catcode239=9 %This is for escaping BOM characters' 
			file.puts  	'\catcode187=9 %This is for escaping BOM characters' 
			file.puts  	'\catcode191=9 %This is for escaping BOM characters' 
			file.puts  	'\input{structure.tex}'
			file.puts  	'\end{document}'
		end
	end

	
	
	def build_structure_file(source_folder_root)
		File.open($output_folder_latex+'/structure.tex',"w") do |file|
			file.puts '\input{preface.tex}'
			onetimer = true;
			Dir.glob($input_folder_original_book +'/*/') do |chapter_folder|
				raw_chapter_name =  File.basename(chapter_folder)
				if raw_chapter_name.start_with?("[ignore]") then next end
				chapter_number = raw_chapter_name.split(' ', 2)[0] #currently not needed
				chapter_name = raw_chapter_name.split(' ', 2)[1]
				if chapter_name == nil then next end
				file.puts '\chapter{'+chapter_name+'}'
				file.puts '\addcontentsline{que}{part}{'+chapter_name+'}'
				# insert page counter reset after first chapter declaration
				if onetimer then
					onetimer = false;
					file.puts '\setcounter{page}{1}'
					file.puts '\pagenumbering{arabic}'					
				end
				Dir.glob(chapter_folder+"/*") do |file_path|
					subchapter_number = File.basename(file_path).split(' ', 2)[0]
					subchapter_file = File.basename(file_path).split(' ', 2)[1]
					if subchapter_file == nil then next end
					subchapter_name = File.basename(subchapter_file,".docx" )
					file.puts '\section{'+subchapter_name+'}' unless subchapter_name.include? '[Main]'
					file.puts '\addcontentsline{que}{chapter}{'+subchapter_name+'}' unless subchapter_name.include? '[Main]'
					file.puts '\input{'+subchapter_number+'.tex}'
				end
				# uncomment for bibliography per chapter
				#file.puts '\printbibliography[title=Zdroje,heading=section]{}'
			end
			# and comment this one
			file.puts '\printbibliography[title=Zdroje]{}'
			file.puts '\\addcontentsline{toc}{chapter}{Zdroje}'
			file.puts '\appendix'
			file.puts '\input{priloha_slovnik.tex}'
			file.puts '\input{priloha_poster.tex}'
		end
	end
	
	
	def copy_preamble_files
		FileUtils.copy_entry($input_folder_original_book +'/preface.tex', $output_folder_latex + '/preface.tex')
		FileUtils.copy_entry($input_folder_original_book +'/all_bibliography_sources.bib', $output_folder_latex + '/all_bibliography_sources.bib')		
		FileUtils.copy_entry($input_folder_original_book +'/priloha_poster.tex', $output_folder_latex + '/priloha_poster.tex')
		FileUtils.copy_entry($input_folder_original_book +'/priloha_slovnik.tex', $output_folder_latex + '/priloha_slovnik.tex')
		FileUtils.copy_entry($input_folder_original_book +'/titlepage.tex', $output_folder_latex + '/titlepage.tex')
	end
	
	
	
	def build_latex_resource(qalo)
		res = "" 
		#res += '\begin{question}{'+remove_resourceID_prefix(qalo[:id])+'}'		# ID
		res += '\begin{question}{'+qalo[:chapter_wise_number]+'}'		# ID
		res += remove_markup('{'+qalo[:bloom]+'}')						# Bloom level
		res += remove_markup('{'+qalo[:concepts].join(", ")+'}')			# Koncepty
		res +="\n"
		res += qalo[:question].map{|par| latexize_paragraph(par)}.join("\n")	# Odstavce otazky, including images
		res +='\end{question}'
		res +="\n"
		res +='\begin{answer}'
		res +="\n"
		res += qalo[:answer].map{|par| latexize_paragraph(par)}.join("\n")		# Odstavce odpovede, including images
		res +='\end{answer}'
		res +="\n"
		res +="\n"

		res.gsub!('#','\#') # some special chars must be escaped for latex
		res.gsub!('_','\_') # some special chars must be escaped for latex
		res.gsub!('%','\%') # some special chars must be escaped for latex
		
		res = place_correct_figure_references(res)
		#res = place_correct_question_references(res)
		
		return res
	end
	
	
	def remove_resourceID_prefix(docbook_id)
		res = docbook_id.dup
		res.slice!(0,$docbook_resource_id_prefix.length)
		return res
	end
	
	def remove_markup(text)
		res = text.dup
		res.gsub! '<emphasis>', ''
		res.gsub! '<emphasis role="bold">', ''
		res.gsub! '</emphasis>', ''
		return res
	end
	
	def latexize_paragraph(par)
		res =""
		case par[:type]
		when :regular
			res +=place_correct_emphasis(par[:text].strip)+"\n"
		when :bulleted
			res +=paragraph_to_list(par, "itemize")
		when :numbered
			res +=paragraph_to_list(par, "enumerate")
		when :figure
			#TODO images
			res += handle_latex_figure(par) # generates snippet, but also copies the image file
		else
			res +="Unhandled unknown par type"
		end		
	end
	
	def paragraph_to_list(par, type)		# type denotes latex environment to be used (either itemize or enumerate)
		res = '\begin{'+type+"}\n"
		res +=par[:list].map{|line| "\t"+'\item '+ place_correct_emphasis(line.strip)}.join("\n")
		res +="\n"+'\end{'+type+"}\n"
	end
	
	def place_correct_emphasis(text)		# replaces all docbook inline markup for emphasis with latex one
		res = text.dup
		res.gsub! '<emphasis>', '\textit{'
		res.gsub! '<emphasis role="bold">', '\textbf{'
		res.gsub! '</emphasis>', '}'
		return res
	end

	def handle_latex_figure(figure_par)
		#TODO POZOR aj tu je .png natvrdo
		$latex_image_counter +=1
		target_file_name = $latex_image_counter.to_s + ".png"
		begin
			FileUtils.cp(figure_par[:source],$output_folder_latex_images+'/'+target_file_name)
		rescue
			p "sakra"
		end
		
		p figure_par[:ID]
		
		# image behavior in latex
		if $image_config.has_key?(figure_par[:ID])
			# draw from config
			flags = $image_config[figure_par[:ID]][:flags]
			scale = $image_config[figure_par[:ID]][:scale]
		else
			# default behavior
			flags ='htb'
			scale ='0.9'
		end
		
		res = ""
		res +="\n"
		res += '\begin{figure}['+flags+']'
		res +="\n"
		res += '\centering'
		res +="\n"
		res += '\includegraphics[width='+scale+'\columnwidth]{images/'+target_file_name+'}'
		res +="\n"
		res += '\caption{'+remove_markup(figure_par[:caption])+'}' unless figure_par[:caption] == nil
		res +="\n"
		res += '\label{'+figure_par[:ID]+'}' unless figure_par[:ID] == nil
		res +="\n"
		res += '\end{figure}'
		res +="\n"
		
		if $image_config.has_key?(figure_par[:ID])
			if ($image_config[figure_par[:ID]][:clearpage_after].equal? 1)
				res += '\clearpage'
				res +="\n"
			end
		end
		
		return res;
	end
	
	def place_correct_figure_references(text)
		res = text.dup
		res.gsub!(/\[\[/,'\ref{')
		res.gsub!(/\]\]/,'}')
		return res
		#res.match(/\[\[(.*?)\]\]/).each do ||
	end

	def place_correct_question_references(text)
		res = text.dup
		res.scan(/\*\*(.*?)\*\*/).each do |match|
			label = match[0]
			if $labels_to_structured_numbers[label] == nil then
				p "referencing non-existing question label " + label
			else
				res.gsub!('**'+label+'**', $labels_to_structured_numbers[label]) 
			end
		end
		return res
		#res.match(/\[\[(.*?)\]\]/).each do ||
	end
end


#=====================================================
#TEMPORALILY ORPHANED METHODS
def get_extractor_filled_with_qalos(paragraph_reader)
	#instantiate state machines
	extractor = Extractor.new
	bulleted_list_detector = Bulleted_list_detector.new extractor
	numbered_list_detector = Numbered_list_detector.new extractor
	figure_detector = Figure_detector.new extractor

	# Fire events over state machines according to paragraphs found
	paragraph_reader.paragraphs.each do |par| 
		bulleted_list_detector.send(par[:style].downcase+'_found', par)
		numbered_list_detector.send(par[:style].downcase+'_found', par)
		figure_detector.send(par[:style].downcase+'_found', par)
		extractor.send(par[:style].downcase+'_found', par)
	end

	#finalizing sequences for machines
	bulleted_list_detector.other_found
	numbered_list_detector.other_found
	figure_detector.other_found
	extractor.finalize
	return extractor
end


#=====================================================
# MAIN SCRIPT


$log = Logger.new(STDOUT)
$log.level = Logger::FATAL

#p __ENCODING__.name

FileUtils.rm_r $output_folder if Dir.exists? $output_folder
FileUtils.rm_r $input_folder_working_book if Dir.exists? $input_folder_working_book

FileUtils.mkdir_p $output_folder
FileUtils.mkdir_p $output_folder_latex
FileUtils.mkdir_p $output_folder_latex_images
FileUtils.mkdir_p $output_folder_docbook
FileUtils.mkdir_p $output_folder_docbook_resources

# unzip the book
zipper = Zipper.new
FileUtils.copy_entry($input_folder_original_book, $input_folder_working_book)
Dir.glob($input_folder_working_book +'/*/*.docx') { |docx_file| 
	next if docx_file.include? '[ignore]'
	zipper.unzip_word_XML(docx_file, File.dirname(docx_file))
}

# extract QALOs (in groups still by source files, e.g. subchapters)
subchapter_extractors = []
Dir.glob($input_folder_working_book  +'/**/*.document.xml') do |source_file|
	next if source_file.include? "[ignore]"
	$log.info ("Processing file" + source_file)
	paragraph_reader = Paragraph_reader.new source_file #TODO refactor, so it is not constructor
	extractor_with_qalos = get_extractor_filled_with_qalos(paragraph_reader)
	extractor_with_qalos.original_file_path = source_file
	subchapter_extractors << extractor_with_qalos
end


# construct docbook
$labels_to_numbers = {} #for translating question labels to numbers
@docbook_resource_number = 0
subchapter_extractors.each do |extractor|
	docbook_builder = Docbook_builder.new
	extractor.qalos.each do |qalo|
		if qalo == nil then p extractor.qalos end
		@docbook_resource_number += 1
		qalo[:docbook_number] = @docbook_resource_number #pomoooc, pouziva sa to aj v latexe
		$labels_to_numbers[qalo[:label]] = qalo[:docbook_number] unless qalo[:label] == nil     # TODO sem musi ist strukturovane cislo, nejak
		qalo[:id] = $docbook_resource_id_prefix + @docbook_resource_number.to_s
		target_file = $output_folder_docbook + '/' + $docbook_resource_file_prefix + @docbook_resource_number.to_s + ".xml" 
		docbook_builder.build_ALEF_resource(target_file, qalo)
	end
end

# construct latex
latexer = Latexer.new
latexer.build_master_file
latexer.build_structure_file $input_folder_unzipped_book
latexer.copy_preamble_files
$labels_to_structured_numbers ={}
log_table_file = File.open('concepts.txt', 'w');
subchapter_extractors.each do |extractor|
	# postprocess from the QALO structure to LaTeX structs
	subchapter_number =  File.basename(extractor.original_file_path).split(' ', 2)[0]
	chapter_number_prefix = subchapter_number.split('.')[0].to_i.to_s + "." + subchapter_number.split('.')[1].to_i.to_s + "."
	latex_file_path = File.join($output_folder_latex, File.basename(subchapter_number, '.xml') + ".tex")
	latexer = Latexer.new
	File.open(latex_file_path, 'w') do |f| 
		extractor.qalos.each_with_index do |qalo, index|
			chapter_wise_number = chapter_number_prefix + (index+1).to_s
			qalo[:chapter_wise_number] = chapter_wise_number
			$labels_to_structured_numbers[qalo[:label]] = chapter_wise_number;
			resource = latexer.build_latex_resource(qalo)
			f.write(resource.encode('UTF-8'))
			#TODO sem este bachnut logovanie koncept-id-znenie otazky
			log_table_id = chapter_wise_number;
			log_table_question = qalo[:question].map{|par| par[:text]}.join("\n");
			log_table_question.gsub!(/(<[^>]*>)|\n|\t/) {" "}
			log_table_question.downcase!
			qalo[:concepts].each do |log_table_concept|
				#p log_table_concept
				#p log_table_id
				#p log_table_question
				log_table_file.write(log_table_concept+";"+log_table_id+";"+log_table_question+"\n")
			end
		end
	end
	
	p 'pik'
	file_name = File.basename(latex_file_path)
	#system 'powershell.exe "gc -en utf8 ./output/latex/'+ file_name +'"'
	system 'powershell.exe "gc -en utf8 ../output/latex/'+ file_name +' | Out-File -en utf8 ../output/latex/_'+file_name+'"'
	FileUtils.cp($output_folder_latex +'/_'+file_name, $output_folder_latex +"/"+file_name)
	FileUtils.rm($output_folder_latex +'/_'+file_name)
end
log_table_file.close

# this is for replacing question references
Dir.glob($output_folder_latex  +'/*.tex')  do |file_name|
	text = File.read(file_name)
	new_content = text.dup
	new_content.scan(/\*\*(.*?)\*\*/).each do |match|
		label = match[0]
		if $labels_to_structured_numbers[label] == nil then
			p "referencing non-existing question label " + label
		else
			new_content.gsub!('**'+label+'**', $labels_to_structured_numbers[label]) 
		end
	end
	File.open(file_name, "w") {|file| file.puts new_content }
end

	#res = place_correct_question_references(res)


system 'powershell.exe "gc ../output/latex/structure.tex | Out-File -en utf8 ../output/latex/_structure.tex"'
FileUtils.cp($output_folder_latex +'/_structure.tex', $output_folder_latex +'/structure.tex')
FileUtils.rm($output_folder_latex +'/_structure.tex')
FileUtils.cp('knizka.sty', $output_folder_latex +'/knizka.sty')
FileUtils.cp('generate_latex_pdf.bat', $output_folder_latex +'/generate_latex_pdf.bat')
#system 'powershell.exe "gc ./output/latex/master.tex | Out-File -en utf8 ./output/latex/_master.tex"'
#FileUtils.cp($output_folder_latex +'/_master.tex', $output_folder_latex +'/master.tex')
#FileUtils.rm($output_folder_latex +'/_master.tex')

