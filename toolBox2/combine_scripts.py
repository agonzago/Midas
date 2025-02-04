#%%
import os

def combine_scripts(output_file, *input_files):
    """
    Combines multiple Python scripts into one file.

    :param output_file: The name of the output file where all scripts will be combined.
    :param input_files: List of input Python files to combine.
    """
    with open(output_file, 'w') as outfile:
        for input_file in input_files:
            # Optionally, you can add a comment indicating the source file
            outfile.write(f"# --- Start of {input_file} ---\n")
            
            # Read the content of the input file
            with open(input_file, 'r') as infile:
                outfile.write(infile.read())
            
            # Optionally, add a separator or comment indicating the end of the file
            outfile.write(f"\n# --- End of {input_file} ---\n\n")

# List of Python files to combine
files_to_combine = ['gpmcast_config.py', 'gopmcast_models.py','gpmcast_data_handling.py',
'gpmcast_models.py', 'generate_data.py', 'test_gpmcast.py']

# Output file name
# Get the directory where the script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
print(script_dir)    
print("Files in directory:", os.listdir())
# Change the current working directory to the script's directory
os.chdir(script_dir)

output_filename = 'gpmcats_script.py'

# Call the function to combine the scripts
combine_scripts(output_filename, *files_to_combine)

print(f"All scripts have been combined into {output_filename}")