$work_folder = Dir.pwd

$input_folder 					= $work_folder + '/input'
$input_folder_original_book		= $work_folder + '/input/Kniha-PSI-MSI-MIS_big' # here, the very source should be placed
$input_folder_working_book 		= $work_folder + '/input/Kniha-PSI-MSI-MIS_working'

$output_folder 					= $work_folder + '/output'
$output_folder_latex 				= $work_folder + '/output/latex'
$output_folder_latex_images		= $work_folder + '/output/latex/images'
$output_folder_docbook 			= $work_folder + '/output/docbook'
$output_folder_docbook_resources	= $work_folder + '/output/docbook/resources'

$docbook_resource_folder_relative 	= "resources/"
$docbook_resource_file_prefix 		= "question-"
$docbook_resource_id_prefix 		= "book-question-answer-" #TODO je to spravne?

$encoding_environment 			= 'Windows-1250'
$encoding_source				= 'UTF-8'

$latex_image_counter			= 0