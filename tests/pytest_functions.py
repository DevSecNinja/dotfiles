import os
import pytest

def get_functions():
    root_dir = os.path.join(os.path.dirname(__file__), '..')
    for folder in ['functions', 'bin']:
        folder_dir = os.path.join(root_dir, folder)
        for filename in os.listdir(folder_dir):
            if not '.' in filename and not filename.startswith('_'):
                with open(os.path.join(folder_dir, filename), 'r') as f:
                    function_content = f.read()
                yield folder, filename, function_content

@pytest.mark.parametrize("folder_name,function_name,function_content", get_functions())
def test_help_parameters(folder_name, function_name, function_content):
    help_param_present = ('-h' in function_content or
                          '--help' in function_content)
    assert help_param_present, f"{function_name} is missing help parameter."

@pytest.mark.parametrize("folder_name,function_name,function_content", get_functions())
def test_shebang_line(folder_name,function_name, function_content):
    shebang_line_present = function_content.startswith("#!")
    assert shebang_line_present, f"{function_name} is missing a shebang line."

@pytest.mark.parametrize("folder_name,function_name,function_content", get_functions())
def test_filename_hyphens(folder_name,function_name, function_content):
    underscore_present = '_' in function_name
    assert not underscore_present, f"{function_name} contains underscore(s) instead of hyphen(s)."
