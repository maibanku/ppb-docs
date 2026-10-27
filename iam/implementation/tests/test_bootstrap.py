import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'bootstrap.py'
spec = importlib.util.spec_from_file_location('ppb_bootstrap', SOURCE)
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def git(path, *args):
    return subprocess.run(['git', '-C', str(path), *args], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout.strip()


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'ppb-base'
        self.repo.mkdir()
        git(self.repo, 'init', '-b', 'main')
        git(self.repo, 'config', 'user.email', 'fixture@example.invalid')
        git(self.repo, 'config', 'user.name', 'Fixture')
        (self.repo/'README.md').write_text('fixture\n')
        git(self.repo, 'add', 'README.md')
        git(self.repo, 'commit', '-m', 'fixture')
        git(self.repo, 'remote', 'add', 'origin', 'https://github.com/maibanku/ppb-base.git')

    def test_clean_expected_repository(self):
        boot.validate_repository(self.repo, 'ppb-base')

    def test_dirty_preserves_content(self):
        (self.repo/'README.md').write_text('user change\n')
        with self.assertRaises(boot.SetupError):
            boot.validate_repository(self.repo, 'ppb-base')
        self.assertEqual((self.repo/'README.md').read_text(), 'user change\n')
        self.assertEqual(git(self.repo, 'branch', '--show-current'), 'main')

    def test_untracked_file_is_not_deleted(self):
        (self.repo/'user.txt').write_text('keep')
        with self.assertRaises(boot.SetupError):
            boot.validate_repository(self.repo, 'ppb-base')
        self.assertEqual((self.repo/'user.txt').read_text(), 'keep')

    def test_wrong_remote_rejected(self):
        git(self.repo, 'remote', 'set-url', 'origin', 'https://github.com/other/ppb-base.git')
        with self.assertRaises(boot.SetupError):
            boot.validate_repository(self.repo, 'ppb-base')

    def test_nested_directory_rejected(self):
        sub = self.repo/'nested'; sub.mkdir()
        with self.assertRaises(boot.SetupError):
            boot.validate_repository(sub, 'ppb-base')

    def local_origin(self):
        origin=self.root/'origin.git'
        subprocess.run(['git', 'clone', '--bare', str(self.repo), str(origin)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        git(self.repo,'remote','set-url','origin',str(origin))
        return origin

    def test_create_branch_from_main(self):
        self.local_origin()
        state=boot.prepare_branch(self.repo, boot.DEFAULT_BRANCH)
        self.assertEqual(state['branch'],boot.DEFAULT_BRANCH)
        self.assertEqual(state['commit'],git(self.repo,'rev-parse','origin/main'))

    def test_track_existing_remote_feature(self):
        origin=self.local_origin()
        git(origin,'branch',boot.DEFAULT_BRANCH,'main')
        boot.prepare_branch(self.repo,boot.DEFAULT_BRANCH)
        self.assertEqual(git(self.repo,'rev-parse','--abbrev-ref','@{upstream}'), 'origin/'+boot.DEFAULT_BRANCH)

    def test_preserve_existing_local_feature_commit(self):
        self.local_origin()
        git(self.repo,'switch','-c',boot.DEFAULT_BRANCH)
        (self.repo/'progress.txt').write_text('existing implementation')
        git(self.repo,'add','progress.txt');git(self.repo,'commit','-m','existing progress')
        before=git(self.repo,'rev-parse','HEAD')
        git(self.repo,'switch','main')
        state=boot.prepare_branch(self.repo,boot.DEFAULT_BRANCH)
        self.assertEqual(state['commit'],before)
        self.assertTrue((self.repo/'progress.txt').exists())

    def test_check_only_does_not_create_directories(self):
        target=self.root/'absent'
        self.assertEqual(boot.main(['--root',str(target),'--check-only']),0)
        self.assertFalse(target.exists())

    def test_main_branch_rejected(self):
        with self.assertRaises(boot.SetupError):
            boot.main(['--root',str(self.root),'--branch','main','--check-only'])

    def test_missing_claude_is_explicit(self):
        with patch.object(boot.shutil,'which',return_value=None):
            with self.assertRaises(boot.SetupError):
                boot.launch(self.root,self.repo/'prompt.md',boot.DEFAULT_BRANCH)

    def test_launch_is_scoped_and_has_no_bypass(self):
        calls=[]
        def fake(args,**kwargs):
            calls.append((args,kwargs))
            text = '--append-system-prompt-file --add-dir --permission-mode' if '--help' in args else 'fixture'
            return subprocess.CompletedProcess(args,0,stdout=text,stderr='')
        with patch.object(boot.shutil,'which',return_value='/fake/claude'),patch.object(boot,'run',side_effect=fake):
            self.assertEqual(boot.launch(self.root,self.repo/'prompt.md',boot.DEFAULT_BRANCH),0)
        command,cfg=calls[-1]
        self.assertEqual(cfg['cwd'],self.root)
        self.assertEqual(command.count('--add-dir'),4)
        self.assertIn('--append-system-prompt-file',command)
        self.assertIn('acceptEdits',command)
        self.assertNotIn('--dangerously-skip-permissions',command)


if __name__ == '__main__':
    unittest.main()
