import sys
from PIL import Image
files=sys.argv[2:]; out=sys.argv[1]
ims=[Image.open(f) for f in files]
w,h=ims[0].size
cols=min(4,len(ims)); rows=(len(ims)+cols-1)//cols
M=Image.new('RGB',(cols*w,rows*h),'white')
for i,im in enumerate(ims): M.paste(im,((i%cols)*w,(i//cols)*h))
M.save(out)
