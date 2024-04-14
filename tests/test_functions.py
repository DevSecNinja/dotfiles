import os
import subprocess
import unittest

class TestFunctionsHelp(unittest.TestCase):

    def get_functions(self):
        functions_dir = os.path.join(os.path.dirname(__file__), '..', 'functions')
        for filename in os.listdir(functions_dir):
            if not '.' in filename and not filename.startswith('_'):
                with open(os.path.join(functions_dir, filename), 'r') as f:
                    function_content = f.read()
                yield filename, function_content

    def test_help_parameters(self):
        for function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name):
                help_param_present = ('-h' in function_content or
                                      '--help' in function_content)
                self.assertTrue(help_param_present, f"{function_name} is missing help parameter.")

    def test_shebang_line(self):
        for function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name):
                shebang_line_present = function_content.startswith("#!")
                self.assertTrue(shebang_line_present, f"{function_name} is missing a shebang line.")

    def test_filename_hyphens(self):
        for function_name, function_content in self.get_functions():
            with self.subTest(function_name=function_name):
                underscore_present = '_' in function_name
                self.assertFalse(underscore_present, f"{function_name} contains underscore(s) instead of hyphen(s).")


if __name__ == "__main__":
    unittest.main(verbosity=2)
