#!/usr/bin/env python3
#
# Copyright (C) 2024 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import argparse
import asyncio
import dataclasses
import os
import re
import shlex
import subprocess
import sys
import tempfile

_STGDIFF_ENV_KEY = 'STGDIFF'
_STGDIFF_BIN = (
    os.environ[_STGDIFF_ENV_KEY]
    if _STGDIFF_ENV_KEY in os.environ
    else 'stgdiff'
)
_STGDIFF_NO_DIFF_STATUS = 0
_STGDIFF_DIFF_STATUS = 4
_PREAMBLE_FORMAT = '# ABI freeze commit: {from_commit}\n'


class FullCalledProcessError(subprocess.CalledProcessError):

  def __str__(self):
    message = super().__str__()
    if self.stdout:
      message += f'\nstdout:\n{self.stdout}'
    if self.stderr:
      message += f'\nstderr:\n{self.stderr}'
    return message


def get_abi_format(abi_path: str) -> str:
  """Get the ABI format from the ABI file name."""
  if abi_path.endswith('.xml'):
    return 'abi'
  elif abi_path.endswith('.stg'):
    return 'stg'
  else:
    raise ValueError(f'Unsupported ABI format: {abi_path}')


def get_git_and_relative_path(abi_path: str) -> tuple[str, str]:
  """Get git top level and path to an ABI file relative to it."""
  abi_dir, abi_filename = os.path.split(abi_path)
  cmd = ['git', '-C', abi_dir, 'rev-parse', '--show-toplevel', '--show-prefix']
  result = subprocess.run(
      cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
  )
  if result.returncode != 0:
      raise FullCalledProcessError(
          returncode=result.returncode,
          cmd=cmd,
          output=result.stdout,
          stderr=result.stderr,
      )
  toplevel, prefix = result.stdout.strip().split('\n')
  return toplevel, os.path.join(prefix, abi_filename)


def get_commit_from_known_abi_breaks(known_abi_breaks: str) -> str:
  """Get the last commit from the known ABI breaks list."""
  preamble_re = re.compile(
      _PREAMBLE_FORMAT.format(from_commit='(?P<from_commit>[0-9a-f]+)')
  )
  match = preamble_re.match(known_abi_breaks)
  if not match:
    raise ValueError('The ABI breaks list does not have a valid preamble')
  return match.group('from_commit')


def get_commits(git: str, abi_file: str, from_commit: str) -> list[str]:
  """Get commits changing the ABI file ordered from oldest to newest."""
  cmd = [
      'git', '-C', git, 'log', '--reverse', '--first-parent', '--pretty=%H',
      f'{from_commit}..HEAD', '--', abi_file
  ]
  result = subprocess.run(
      cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True
  )
  # Add from_commit to the list manually, because "git log {from_commit}..HEAD"
  # would not include it.
  return [from_commit] + list(result.stdout.split())


def get_stg_compatibility_check_options(input_format: str) -> list[str]:
  """Builds comparison and options for ABI compatibility checks with STG."""
  options = [
      '--ignore',
      'interface_addition',
      '--ignore',
      'type_definition_addition',
      '--format',
      'short',
  ]
  if input_format == 'abi':
    for ignore_option in ['symbol_type_presence', 'type_declaration_status']:
      options.extend(['--ignore', ignore_option])
  return options


@dataclasses.dataclass(frozen=True, kw_only=True)
class AbiCompatibilityReport:
  commit_hash1: str = ''
  commit_hash2: str = ''
  compatible: bool
  report: str = ''


class AbiCompatibilityReportsCollector:
  """Collects ABI compatibility reports through ABI file versions."""

  _git: str
  _abi_file: str
  _abi_format: str
  _temp_dir: str
  _loop: asyncio.AbstractEventLoop
  _semaphore: asyncio.Semaphore
  _abi_file_cache: dict[str, str]

  def __init__(
      self,
      git: str,
      abi_file: str,
      abi_format: str,
      temp_dir: str,
      max_workers: int,
  ):
    self._git = git
    self._abi_file = abi_file
    self._abi_format = abi_format
    self._temp_dir = temp_dir
    self._semaphore = asyncio.Semaphore(max_workers)
    self._loop = asyncio.get_event_loop()

  async def _get_abi_file(self, commit_hash: str) -> str:
    """Get the ABI file version at the given commit hash."""
    async with self._semaphore:
      output = f'{self._temp_dir}/{commit_hash}'
      assert not os.path.exists(output)
      cmd = shlex.join(
          ['git', '-C', self._git, 'show', f'{commit_hash}:{self._abi_file}']
      )
      cmd += f' > {shlex.quote(output)}'
      process = await asyncio.create_subprocess_shell(
          cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
      )
      stdout, stderr = await process.communicate()
      if process.returncode != 0:
        raise FullCalledProcessError(
            returncode=process.returncode,
            cmd=cmd,
            output=stdout.decode(),
            stderr=stderr.decode(),
        )
    return output

  async def _compare(
      self, abi_file1: str, abi_file2: str
  ) -> AbiCompatibilityReport:
    """Check ABI compatibility between two ABI files."""
    cmd = shlex.join(
        [_STGDIFF_BIN]
        + get_stg_compatibility_check_options(self._abi_format)
        + [
            f'--{self._abi_format}',
            abi_file1,
            abi_file2,
            '--output',
            '/dev/stdout',
        ]
    )
    process = await asyncio.create_subprocess_shell(
        cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    stdout, stderr = await process.communicate()
    if process.returncode not in (
        _STGDIFF_NO_DIFF_STATUS,
        _STGDIFF_DIFF_STATUS,
    ):
      raise FullCalledProcessError(
          returncode=process.returncode,
          cmd=cmd,
          output=stdout.decode(),
          stderr=stderr.decode(),
      )

    return AbiCompatibilityReport(
        commit_hash1=os.path.basename(abi_file1),
        commit_hash2=os.path.basename(abi_file2),
        compatible=process.returncode == _STGDIFF_NO_DIFF_STATUS,
        report=stdout.decode(),
    )

  async def _compare_with_current(
      self,
      abi_file_future: asyncio.Task[str],
      current_abi_file: str,
  ) -> AbiCompatibilityReport:
    """Await for the ABI file and compare it with the current ABI file."""
    abi_file = await abi_file_future
    return await self._compare(abi_file, current_abi_file)

  async def get_reports_async(
      self, commit_hashes: list[str], current_abi_file: str
  ) -> list[AbiCompatibilityReport]:
    """Get ABI compatibility reports between commits (async version)."""
    abi_files = {
        commit_hash: asyncio.create_task(self._get_abi_file(commit_hash))
        for commit_hash in commit_hashes
    }
    reports = []
    for commit_hash in commit_hashes:
      reports.append(
          self._compare_with_current(abi_files[commit_hash], current_abi_file)
      )
    return await asyncio.gather(*reports)

  def get_reports(
      self, commit_hashes: list[str], current_abi_file: str
  ) -> list[AbiCompatibilityReport]:
    """Get ABI compatibility reports between commits."""
    return self._loop.run_until_complete(
        self.get_reports_async(commit_hashes, current_abi_file)
    )


class KnownAbiBreaks:
  """Builds a list of known ABI breaks."""
  breaks_set: set[str]
  breaks_list: list[str]

  def __init__(self):
    self.breaks_set = set()
    self.breaks_list = []

  def _split_report(self, report):
    return [chunk.strip() for chunk in report.split('\n\n') if chunk]

  def add_report(self, report):
    breaks = self._split_report(report)
    for break_ in breaks:
      if break_ not in self.breaks_set:
        self.breaks_set.add(break_)
        self.breaks_list.append(break_)


def main():
  """Extracts ABI breaks between development branch and active releases."""
  parser = argparse.ArgumentParser()
  parser.add_argument(
      '--abi', required=True, help='Path to the ABI representaion'
  )
  parser.add_argument(
      '--known-abi-breaks',
      required=True,
      help='ABI breaks list to update',
  )
  parser.add_argument(
      '--jobs',
      type=int,
      default=os.cpu_count(),
      help='Number of parallel jobs to run (default: %(default)s)',
  )

  args = parser.parse_args()
  if not os.path.exists(args.abi):
    raise ValueError(f'ABI file does not exist: {args.abi}')
  abi_format = get_abi_format(args.abi)
  git, abi_file = get_git_and_relative_path(args.abi)
  known_abi_breaks = KnownAbiBreaks()

  if not os.path.exists(args.known_abi_breaks):
    raise ValueError(
        f'The ABI breaks list {args.known_abi_breaks} does not exist'
    )
  with open(args.known_abi_breaks, 'r') as f:
    content = f.read()
    from_commit = get_commit_from_known_abi_breaks(content)
    content_without_comments = '\n'.join(
        line for line in content.split('\n') if not line.startswith('#')
    )
    known_abi_breaks.add_report(content_without_comments)

  commits = get_commits(git, abi_file, from_commit)
  if not commits:
    raise RuntimeError(
        f'ABI file has no history from commit {from_commit}, are you sure the'
        ' commit belongs to the branch you are at?'
    )
  with tempfile.TemporaryDirectory() as temp_dir:
    abi_reports_collector = AbiCompatibilityReportsCollector(
        git, abi_file, abi_format, temp_dir, args.jobs
    )
    abi_reports = abi_reports_collector.get_reports(commits, args.abi)
    for report in abi_reports:
      if not report.compatible:
        known_abi_breaks.add_report(report.report)

  with open(args.known_abi_breaks, 'w') as f:
    f.write(_PREAMBLE_FORMAT.format(from_commit=from_commit))
    for break_ in known_abi_breaks.breaks_list:
      f.write(break_)
      f.write('\n\n')


if __name__ == '__main__':
  sys.exit(main())
