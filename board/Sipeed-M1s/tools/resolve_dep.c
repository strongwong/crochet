/*
BSD 3-Clause License

Copyright (c) 2023, Virus.V

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <gelf.h>
#include <libelf.h>

#include <sys/queue.h>

STAILQ_HEAD(library_list, entry)
library_head = STAILQ_HEAD_INITIALIZER(library_head);
struct entry {
  char *url;
  STAILQ_ENTRY(entry) entries; /* Tail queue. */
} *last_process;

struct search_param {
  const char *name;
  int result;
};

static int search_library(const char *name);
static int traverse_dir(char *const path, int (*check)(void *ctx, const char *, const char *, struct stat *), void *ctx);

static int
insert_library(const char *url)
{
  struct entry *e, *np;

  /* find file already exist? */
  STAILQ_FOREACH(np, &library_head, entries) {
    if (strcmp(np->url, url) == 0) {
      return 0;
    }
  }

  /* create new node */
  e = malloc(sizeof(struct entry));
  assert(e != NULL);

  e->url = strdup(url);
  assert(e->url != NULL);

  STAILQ_INSERT_TAIL(&library_head, e, entries);

  return 0;
}

static int check_executable(const char *fname, int fd, int *is_shlib) {
  Elf *elf;
  GElf_Ehdr ehdr;
  Elf_Scn *section;
  GElf_Shdr shdr;
  Elf_Data *dyn_data;

  GElf_Dyn dyn_entry, *curr_dyn_entry;

  char dynamic = 0;
  int i, j;
  size_t dyn_entry_count;

  int ret = 1;

  if (elf_version(EV_CURRENT) == EV_NONE) {
    fprintf(stderr, "unsupported libelf\n");
    return ret;
  }

  elf = elf_begin(fd, ELF_C_READ, NULL);
  if (elf == NULL) {
    fprintf(stderr, "%s: %s\n", fname, elf_errmsg(0));
    return ret;
  }

  if (elf_kind(elf) != ELF_K_ELF) {
    fprintf(stderr, "%s: not a dynamic ELF executable\n", fname);
    goto _out;
  }

  if (gelf_getehdr(elf, &ehdr) == NULL) {
    fprintf(stderr, "%s: %s\n", fname, elf_errmsg(0));
    goto _out;
  }

  /* is shared library? */
  *is_shlib = ehdr.e_type == ET_DYN;

#if 0
  if (ehdr.e_ident[EI_OSABI] != ELFOSABI_FREEBSD) {
    fprintf(stderr, "%s: not a FreeBSD ELF object\n", fname);
    goto _out;
  }
#endif

  /* get all sections */
  for (i = 0; i < ehdr.e_shnum; i++) {
    if ((section = elf_getscn(elf, i)) == NULL) {
      fprintf(stderr, "%s: %s\n", fname, elf_errmsg(0));
      goto _out;
    }
    assert(section != NULL);

    /* find dynamic section */
    gelf_getshdr(section, &shdr);
    if (shdr.sh_type != SHT_DYNAMIC) {
      continue;
    }

    dynamic = 1;

    /* get dynamic section infos */
    if ((dyn_data = elf_getdata(section, NULL)) == NULL) {
      fprintf(stderr, "%s: %s\n", fname, elf_errmsg(0));
      goto _out;
    }

    dyn_entry_count = shdr.sh_size / shdr.sh_entsize;
    for (j = 0; j < dyn_entry_count; j++) {
      curr_dyn_entry = gelf_getdyn(dyn_data, j, &dyn_entry);
      assert(curr_dyn_entry == &dyn_entry);

      /* find NEEDED tags */
      if (curr_dyn_entry->d_tag == DT_NEEDED) {
        char *name = elf_strptr(elf, shdr.sh_link, curr_dyn_entry->d_un.d_val);
        if (name == NULL) {
          continue;
        }
        ret = 0;

        /* search library files */
        search_library(name);
      }
    }
  }

  if (!dynamic) {
    fprintf(stderr, "%s: not a dynamic ELF executable\n", fname);
    goto _out;
  }

_out:
  elf_end(elf);
  return ret;
}

/* library search path */
const char *libs_path = "lib:usr/lib";

static int
checkso(void *ctx, const char *path, const char *basename, struct stat *st)
{
  struct search_param *param = (struct search_param *)ctx;

  assert(param != NULL);
  assert(param->name != NULL);

  /* if not regular file or not symlink, skip */
  if (!(S_ISREG(st->st_mode) || S_ISLNK(st->st_mode))) {
    return 0;
  }

  /* is found? */
  if (strcmp(param->name, basename) == 0) {
    /* add full path to head */
    insert_library(path);

    /* insert symlink target too */
    if (S_ISLNK(st->st_mode)) {
      char *actualpath = realpath(path, NULL);
      insert_library(actualpath);
      free(actualpath);
    }

    param->result = 1;
    /* stop traverse */
    return 1;
  }
  return 0;
}

static int
search_library(const char *name)
{
  char path[PATH_MAX];
  char *p, *ptr;
  char *libs_path_dup = strdup(libs_path);
  assert(libs_path_dup != NULL);
  struct search_param param;

  param.name = name;
  param.result = 0;

  for (ptr = strtok_r(libs_path_dup, ":", &p); ptr;
       ptr = strtok_r(NULL, ":", &p)) {
    traverse_dir(ptr, checkso, (void *)&param);
  }

  /* not found? */
  if (param.result == 0) {
    fprintf(stderr, "%s not found\n", name);
  }

  return 0;
}

static int
traverse_dir(char *const path, int (*check)(void *ctx, const char *, const char *, struct stat *), void *ctx)
{
  char ep[PATH_MAX];
  DIR *dirp;
  struct dirent entry;
  struct dirent *endp;
  struct stat st;

  snprintf(ep, sizeof(ep), "%s", path);

  if (lstat(ep, &st) == -1)
    return -1;

  if ((dirp = opendir(ep)) == NULL)
    return -1;

  for (;;) {
    endp = NULL;
    if (readdir_r(dirp, &entry, &endp) == -1) {
      closedir(dirp);
      return -1;
    }

    if (endp == NULL)
      break;
    assert(endp == &entry);

    if (strcmp(entry.d_name, ".") == 0 || strcmp(entry.d_name, "..") == 0)
      continue;

    snprintf(ep, sizeof(ep), "%s/%s", path, entry.d_name);

    if (lstat(ep, &st) == -1) {
      closedir(dirp);
      return -1;
    }

    if (check(ctx, ep, entry.d_name, &st)) {
      return 0;
    }

    if (S_ISDIR(st.st_mode) == 0)
      continue;
    traverse_dir(ep, check, ctx);
  }
  closedir(dirp);
  return 0;
}

static void
usage(void)
{
  fprintf(stderr, "usage: resolve_dep [-L paths] program ...\n");
  exit(1);
}

int main(int argc, char *argv[]) {
  int fd, is_shlib;
  struct entry *np;
  int c;
  char *chcwd = NULL;

  while ((c = getopt(argc, argv, "L:C:")) != -1) {
    switch (c) {
    case 'L':
      libs_path = optarg;
      break;
    case 'C':
      chcwd = optarg;
      break;
    default:
      usage();
      /* NOTREACHED */
    }
  }

  argc -= optind;
  argv += optind;

  if (argc <= 0) {
    usage();
    /* NOTREACHED */
  }

  if (chcwd != NULL) {
    if (chdir(chcwd) < 0) {
      perror("chdir");
      return 1;
    }
  }

  for (; argc > 0; argc--, argv++) {
    if ((fd = open(*argv, O_RDONLY | O_VERIFY, 0)) < 0) {
      perror("open");
      return 1;
    }

    /* get bin shared library */
    check_executable(*argv, fd, &is_shlib);
    close(fd);
  }

  /* process all shared librarys */
  while (last_process != STAILQ_LAST(&library_head, entry, entries)) {

    STAILQ_FOREACH(np, &library_head, entries) {
      if ((fd = open(np->url, O_RDONLY | O_VERIFY, 0)) < 0) {
        perror("open");
        return 1;
      }

      check_executable(np->url, fd, &is_shlib);
      close(fd);
    }

    last_process = STAILQ_LAST(&library_head, entry, entries);
  }


  STAILQ_FOREACH(np, &library_head, entries) {
    printf("%s\n", np->url);
  }

  fflush(stdout);
  return 0;
}
