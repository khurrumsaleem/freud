#include "fastio.h"

/* Compiling on windows */
#if defined(_MSC_VER)

#if 1 

static int fio_win32convertfilename(const char *filename, char *newfilename, int maxlen) {
  int i;
  int len=strlen(filename);
 
  if ((len + 1) >= maxlen)
    return -1;
   
  for (i=0; i<len; i++) {
    if (filename[i] == '/')
      newfilename[i] = '\\';
    else
      newfilename[i] = filename[i];
  }
  newfilename[len] = '\0'; /* NUL terminate the string */

  return 0;
}

static int fio_open(const char *filename, int mode, fio_fd *fd) {
  HANDLE fp;
  char winfilename[8192];
  DWORD access;
  DWORD sharing;
  LPSECURITY_ATTRIBUTES security;
  DWORD createmode;
  DWORD flags;

  if (fio_win32convertfilename(filename, winfilename, sizeof(winfilename)))
    return -1;  

  access = 0;
  if (mode & FIO_READ)
    access |= GENERIC_READ;
  if (mode & FIO_WRITE)
    access |= GENERIC_WRITE;
#if 0
  access = FILE_ALL_ACCESS; /* XXX hack if above modes fail */
#endif

  sharing = 0;       /* disallow sharing with other processes  */
  security = NULL;   /* child processes don't inherit anything */

  /* since we never append, blow away anything that's already there */
  if (mode & FIO_WRITE)
    createmode = CREATE_ALWAYS;
  else 
    createmode = OPEN_EXISTING;

  flags = FILE_ATTRIBUTE_NORMAL;

  fp = CreateFile(winfilename, access, sharing, security, 
                  createmode, flags, NULL);

  if (fp == NULL) {
    return -1;
  } else {
    *fd = fp;
    return 0;
  }
}


static int fio_fclose(fio_fd fd) {
  BOOL rc;
  rc = CloseHandle(fd);
  if (rc) 
    return 0;
  else 
    return -1;
}

static fio_size_t fio_fread(void *ptr, fio_size_t size, 
                            fio_size_t nitems, fio_fd fd) {
  BOOL rc;
  DWORD len;
  DWORD readlen;

  len = size * nitems;

  rc = ReadFile(fd, ptr, len, &readlen, NULL);
  if (rc) {
    if (readlen == len)
      return nitems;
    else 
      return 0;
  } else {
    return 0;
  }
}

static fio_size_t fio_readv(fio_fd fd, const fio_iovec * iov, int iovcnt) {
  int i;
  fio_size_t len = 0; 

  for (i=0; i<iovcnt; i++) {
    fio_size_t rc = fio_fread(iov[i].iov_base, iov[i].iov_len, 1, fd);
    if (rc != 1)
      break;
    len += iov[i].iov_len;
  }

  return len;
}

static fio_size_t fio_fwrite(void *ptr, fio_size_t size, 
                             fio_size_t nitems, fio_fd fd) {
  BOOL rc;
  DWORD len;
  DWORD writelen;

  len = size * nitems; 
 
  rc = WriteFile(fd, ptr, len, &writelen, NULL);
  if (rc) {
    if (writelen == len)
      return nitems;
    else
      return 0;
  } else {
    return 0;
  }
}

static fio_size_t fio_fseek(fio_fd fd, fio_size_t offset, int whence) {
#if 1
  /* code that works with older MSVC6 compilers */
  LONGLONG finaloffset;
  LARGE_INTEGER bigint;
  LARGE_INTEGER finalint;

  bigint.QuadPart = offset;
  finalint = bigint;      /* set the high part, which will be overwritten */
  finalint.LowPart = SetFilePointer(fd, bigint.LowPart, &finalint.HighPart, whence);
  if (finalint.LowPart == -1) {
    /* if (finalint.LowPart == INVALID_SET_FILE_POINTER) { */
    /* INVALID_SET_FILE_POINTER is a possible "ok" low order result when */
    /* working with 64-bit offsets, so we have to also check the system  */
    /* error value for this thread to be sure */
    if (GetLastError() != ERROR_SUCCESS) {
      return -1;
    }
  } 

  finaloffset = finalint.QuadPart;
  return 0;
#else
  BOOL rc;
  LONGLONG finaloffset;

  /* SetFilePointerEx() only exists with new .NET compilers */
  rc = SetFilePointerEx(fd, offset, &finaloffset, whence);

  if (rc) 
    return 0;
  else
    return -1;
#endif
}

static fio_size_t fio_ftell(fio_fd fd) {
  /* code that works with older MSVC6 compilers */
  LONGLONG finaloffset;
  LARGE_INTEGER bigint;
  LARGE_INTEGER finalint;

  bigint.QuadPart = 0;
  finalint = bigint;      /* set the high part, which will be overwritten */

  finalint.LowPart = SetFilePointer(fd, bigint.LowPart, &finalint.HighPart, FILE_CURRENT);
  if (finalint.LowPart == -1) {
    /* if (finalint.LowPart == INVALID_SET_FILE_POINTER) { */
    /* INVALID_SET_FILE_POINTER is a possible "ok" low order result when */
    /* working with 64-bit offsets, so we have to also check the system  */
    /* error value for this thread to be sure */
    if (GetLastError() != ERROR_SUCCESS) {
      return -1;
    }
  }

  finaloffset = finalint.QuadPart;

  return finaloffset;
}


#else

/* Version for machines with plain old ANSI C  */

static int fio_open(const char *filename, int mode, fio_fd *fd) {
  char * modestr;
  FILE *fp;
 
  if (mode == FIO_READ) 
    modestr = "rb";

  if (mode == FIO_WRITE) 
    modestr = "wb";

  fp = fopen(filename, modestr);
  if (fp == NULL) {
    return -1;
  } else {
    *fd = fp;
    return 0;
  }
}

static int fio_fclose(fio_fd fd) {
  return fclose(fd);
}

static fio_size_t fio_fread(void *ptr, fio_size_t size, 
                            fio_size_t nitems, fio_fd fd) {
  return fread(ptr, size, nitems, fd);
}

static fio_size_t fio_readv(fio_fd fd, const fio_iovec * iov, int iovcnt) {
  int i;
  fio_size_t len = 0; 

  for (i=0; i<iovcnt; i++) {
    fio_size_t rc = fread(iov[i].iov_base, iov[i].iov_len, 1, fd);
    if (rc != 1)
      break;
    len += iov[i].iov_len;
  }

  return len;
}

static fio_size_t fio_fwrite(void *ptr, fio_size_t size, 
                             fio_size_t nitems, fio_fd fd) {
  return fwrite(ptr, size, nitems, fd);
}

static fio_size_t fio_fseek(fio_fd fd, fio_size_t offset, int whence) {
  return fseek(fd, offset, whence);
}

static fio_size_t fio_ftell(fio_fd fd) {
  return ftell(fd);
}
#endif /* plain ANSI C */

#else 

static int fio_open(const char *filename, int mode, fio_fd *fd) {
  int nfd;
  int oflag = 0;

  if (mode == FIO_READ) 
    oflag = O_RDONLY;

  if (mode == FIO_WRITE) 
    oflag = O_WRONLY | O_CREAT | O_TRUNC;

  nfd = open(filename, oflag, 0666);
  if (nfd < 0) {
    return -1;
  } else {
    *fd = nfd;
    return 0;
  }
}

static int fio_fclose(fio_fd fd) {
  return close(fd);
}

static fio_size_t fio_fread(void *ptr, fio_size_t size, 
                            fio_size_t nitems, fio_fd fd) {
  int i;
  fio_size_t len = 0; 
  int cnt = 0;

  for (i=0; i<nitems; i++) {
    fio_size_t rc = read(fd, (void*) (((char *) ptr) + (cnt * size)), size);
    if (rc != size)
      break;
    len += rc;
    cnt++;
  }

  return cnt;
}

static fio_size_t fio_readv(fio_fd fd, const fio_iovec * iov, int iovcnt) {
#if defined(USE_KERNEL_READV)
  return readv(fd, iov, iovcnt);
#else
  int i;
  fio_size_t len = 0; 

  for (i=0; i<iovcnt; i++) {
    fio_size_t rc = read(fd, iov[i].iov_base, iov[i].iov_len);
    if (rc != iov[i].iov_len)
      break;
    len += iov[i].iov_len;
  }

  return len;
#endif
}

static fio_size_t fio_fwrite(void *ptr, fio_size_t size, 
                             fio_size_t nitems, fio_fd fd) {
  int i;
  fio_size_t len = 0; 
  int cnt = 0;

  for (i=0; i<nitems; i++) {
    fio_size_t rc = write(fd, ptr, size);
    if (rc != size)
      break;
    len += rc;
    cnt++;
  }

  return cnt;
}

static fio_size_t fio_fseek(fio_fd fd, fio_size_t offset, int whence) {
 if (lseek(fd, offset, whence) >= 0)
   return 0;  /* success (emulate behavior of fseek) */
 else 
   return -1; /* failure (emulate behavior of fseek) */
}

static fio_size_t fio_ftell(fio_fd fd) {
  return lseek(fd, 0, SEEK_CUR);
}

#endif


/* higher level routines that are OS independent */

static int fio_write_int32(fio_fd fd, int i) {
  return (fio_fwrite(&i, 4, 1, fd) != 1);
}

static int fio_read_int32(fio_fd fd, int *i) {
  return (fio_fread(i, 4, 1, fd) != 1);
}

static int fio_write_str(fio_fd fd, const char *str) {
  int len = strlen(str);
  return (fio_fwrite((void *) str, len, 1, fd) != 1);
}