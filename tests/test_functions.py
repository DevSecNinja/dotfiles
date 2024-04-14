import os
import subprocess
import unittest

class TestFunctionsHelp(unittest.TestCase):

    def get_functions(self):
        root_dir = os.path.join(os.path.dirname(__file__), '..')
        for folder in ['functions', 'bin']:
            folder_dir = os.path.join(root_dir, folder)
            for filename in os.listdir(folder_dir):
                if not '.' in filename and not filename.startswith('_'):
                    with open(os.path.join(folder_dir, filename), 'r') as f:
                        function_content = f.read()
                    yield folder, filename, function_content

    def test_help_parameters(self):
        for folder, function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name, folder_name=folder):
                help_param_present = ('-h' in function_content or
                                      '--help' in function_content)
                self.assertTrue(help_param_present, f"{function_name} is missing help parameter.")

    def test_shebang_line(self):
        for folder, function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name, folder_name=folder):
                shebang_line_present = function_content.startswith("#!")
                self.assertTrue(shebang_line_present, f"{function_name} is missing a shebang line.")

    def test_filename_hyphens(self):
        for folder, function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name, folder_name=folder):
                underscore_present = '_' in function_name
                self.assertFalse(underscore_present, f"{function_name} contains underscore(s) instead of hyphen(s).")


if __name__ == "__main__":
    unittest.main(verbosity=2)
