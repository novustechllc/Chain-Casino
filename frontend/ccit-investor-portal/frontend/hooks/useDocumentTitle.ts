import { useEffect } from 'react';

interface UseDocumentTitleOptions {
  title: string;
  favicon?: string;
}

export const useDocumentTitle = ({ title, favicon }: UseDocumentTitleOptions) => {
  useEffect(() => {
    // Set document title
    const previousTitle = document.title;
    document.title = title;

    // Set favicon if provided
    let previousFavicon: string | null = null;
    if (favicon) {
      const existingFavicon = document.querySelector('link[rel="icon"]') as HTMLLinkElement;
      if (existingFavicon) {
        previousFavicon = existingFavicon.href;
        existingFavicon.href = favicon;
      } else {
        // Create favicon link if it doesn't exist
        const link = document.createElement('link');
        link.rel = 'icon';
        link.type = 'image/png';
        link.href = favicon;
        document.head.appendChild(link);
      }
    }

    // Cleanup function to restore previous values
    return () => {
      document.title = previousTitle;
      if (favicon && previousFavicon) {
        const faviconLink = document.querySelector('link[rel="icon"]') as HTMLLinkElement;
        if (faviconLink) {
          faviconLink.href = previousFavicon;
        }
      }
    };
  }, [title, favicon]);
}; 