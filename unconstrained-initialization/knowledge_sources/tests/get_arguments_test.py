from unittest.mock import Mock, patch
import pytest

from knowledge_sources.get_arguments import GetArguments

@patch("os.path.exists", True)
@patch('sys.argv', ["scrip.py", "-instance_file", "instance.txt", "-solution_file", "solution.txt"])
def test_verify_missing_time_limit():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()



@patch("os.path.exists", True)
@patch('sys.argv', ["scrip.py","-time_limit_in_ms", "8000", "-solution_file", "solution.txt"])
def test_verify_missing_instance():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()




@patch("os.path.exists", True)
@patch('sys.argv', ["scrip.py","-time_limit_in_ms", "8000", "-instance_file", "instance.txt"])
def test_verify_missing_solution_file():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()



@patch('sys.argv', ["scrip.py", "-instance_file", "instance.txt", "-solution_file", "solution.txt", "-time_limit_in_ms", "8000"])
@patch("os.path.exists", False)
def test_verify_file_not_exist():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    with pytest.raises(FileNotFoundError):
        knowledge_source.verify()



@patch('sys.argv', ["scrip.py", "-instance_file", "instance.txt", "-solution_file", "solution.txt", "-time_limit_in_ms", "coucou"])
@patch("os.path.exists", False)
def test_verify_time_limit_not_numeric():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    with pytest.raises(ValueError):
        knowledge_source.verify()



@patch("os.path.exists", True)
@patch('sys.argv', [ "scrip.py","-instance_file", "instance.txt", "-solution_file", "solution.txt", "-time_limit_in_ms", "8000"])
def test_verify_ok():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)

    assert knowledge_source.verify() == True




@patch("os.path.exists", True)
@patch('sys.argv', [ "scrip.py","-instance_file", "instance.txt", "-solution_file", "solution.txt", "-time_limit_in_ms", "8000"])
def test_process():
    blackboard = Mock()
    knowledge_source = GetArguments(blackboard)
    knowledge_source.process()

    assert blackboard.time_limit == 8
    assert blackboard.instance == "instance.txt"
    assert blackboard.output_file == "solution.txt"
